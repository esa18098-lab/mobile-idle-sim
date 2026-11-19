#!/usr/bin/env python3
"""The balance sheet's Timeline tab, formula for formula, in Python.

The sheet only computes the path its dropdowns are set to. This model
computes any path, so the sim can be checked against the sheet's own maths
for every path. It reads the same CSVs the game reads, and it must reproduce
the sheet's default path exactly (see --check).

  python3 tools/sheet_model.py            # print all paths
  python3 tools/sheet_model.py --golden   # write tests/golden/sheet_paths.csv
  python3 tools/sheet_model.py --check    # compare the default path to the sheet's numbers

Column letters in comments are the Timeline tab's columns.
"""
import csv, math, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(name):
    with open(os.path.join(ROOT, "balance", name + ".csv"), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def num(raw):
    s = str(raw).strip().replace(",", "")
    if s.endswith("%"):
        return float(s[:-1]) / 100.0
    return float(s)


KEY = "Key (used by code)"
P = {r[KEY]: r["Value"] for r in read("inputs") + read("market_settings") if r[KEY]}
def n(k): return num(P[k])

OUT = {r[KEY]: num(r["Output at level 1 (per hr)"]) for r in read("buildings")}
TYPE_BY_NAME = {r["Building"]: r[KEY] for r in read("buildings")}
TERRAIN = {r["Terrain"]: r for r in read("terrain")}
REGIONS = {int(r["Region"]): r for r in read("regions")}
PLAN = {}
for row in read("build_plan"):
    counts = {TYPE_BY_NAME[c]: int(row[c]) for c in row if c in TYPE_BY_NAME}
    PLAN[int(row["Attacking region"])] = {"counts": counts, "avg": num(row["Avg building level"]),
                                           "total": sum(counts.values())}


def market_food_price():
    """Market!B8: the settled price at the sheet's assumed player sales."""
    row = next(r for r in read("market") if r["Resource"] == "Food")
    base, supply, demand = num(row["Base price"]), num(row["NPC supply/hr"]), num(row["NPC demand/hr"])
    sells, sens = num(row["Player sells/hr"]), num(row["Sensitivity"])
    p = base * (demand / (supply + sells)) ** sens
    return min(max(p, base * n("market_price_floor")), base * n("market_price_ceiling"))


def timeline(civ_overrides=None):
    """Returns per-region rows like the Timeline tab. civ_overrides:
    {civ name: {"method": ..., "trade": ..., "captured": ...}}"""
    civs = {}
    for r in read("civilizations"):
        civs[r["Civilization"]] = {"method": r["Method"], "trade": r["Trade rights"].upper() == "TRUE",
                                   "first": int(r["First region"]), "last": int(r["Last region"]),
                                   "captured": r["Captured regions"]}
    for name, o in (civ_overrides or {}).items():
        civs[name].update(o)

    g1, gg = n("garrison_first"), n("garrison_growth")
    K = {i: g1 * gg ** (i - 2) for i in REGIONS if REGIONS[i]["Owner"] != "You"}       # K
    civ_of = {i: REGIONS[i]["Owner"] for i in REGIONS}
    size = {c: sum(K[i] for i in K if civ_of[i] == c) for c in civs}                   # F6:F8
    price = market_food_price()
    adv, margin = n("def_advantage"), n("attack_margin")
    surv_share = math.sqrt(1 - (1 / margin) ** 2)

    rows = []
    E, AR_prev, AU_prev = 0.0, n("starting_soldiers"), "—"
    razes = 0
    for r in range(2, max(REGIONS) + 1):
        reg = REGIONS[r]
        civ = civs[civ_of[r]]
        D = civ["method"]                                                               # D
        Nm = num(TERRAIN[reg["Terrain"]]["Defense mod"])                                 # N
        owned = range(1, r)
        O = sum(int(REGIONS[k]["Slots"]) for k in owned)                                # O
        def avg_mult(col):
            return sum(int(REGIONS[k]["Slots"]) * num(TERRAIN[REGIONS[k]["Terrain"]][col]) for k in owned) / O
        Rm, Sm, Tm = avg_mult("Metal"), avg_mult("Fuel"), avg_mult("Food")              # R S T
        plan = PLAN[r]
        c = plan["counts"]
        Pl = plan["avg"]                                                                # P
        Q = n("level_output_growth") ** (Pl - 1)                                        # Q
        raze_prev = AU_prev == "Raze"
        pen = (1 - n("raze_output_penalty")) if raze_prev else 1.0
        U = c["home"] * OUT["home"] * Q * pen                                           # U
        V = c["farm"] * OUT["farm"] * Q * Tm - U * n("food_per_citizen")               # V
        AT = sum(1 for cv in civs.values() if cv["trade"] and cv["last"] >= r)          # AT
        W = max(V, 0) * n("food_sell_share") * price * (1 - n("market_fee") + n("trade_fee_cut_per_partner") * AT) * pen
        X = max(V, 0) * (1 - n("food_sell_share"))                                      # X
        Y = c["mine"] * OUT["mine"] * Q * Rm                                            # Y
        Z = c["fuel_extractor"] * OUT["fuel_extractor"] * Q * Sm - (c["factory_rations"] + c["factory_equipment"]) * n("factory_fuel_draw") * Q
        if r == 2:
            AA = AB = AC = 0.0
        else:
            prev = PLAN[r - 1]
            J_prev, P_prev = prev["total"], prev["avg"]
            share = 0.0 if AU_prev == "Annex" else (n("occupy_rebuild_share") if AU_prev == "Occupy" else 1.0)
            L_prev = int(REGIONS[r - 1]["Slots"])
            up = J_prev * (Pl - P_prev) * n("upgrade_cost_growth") ** (P_prev - 1)
            AA = share * (O - J_prev) * n("new_building_metal") + up * n("upgrade_metal") - (L_prev * n("raze_metal_per_slot") if raze_prev else 0)
            AB = share * (O - J_prev) * n("new_building_fuel") + up * n("upgrade_fuel") - (L_prev * n("raze_fuel_per_slot") if raze_prev else 0)
            AC = up * n("upgrade_gold")
        AQ = AR_prev                                                                    # AQ
        I = 0 if D == "Annex" else math.ceil(K[r] * adv * Nm * margin - 1e-9)           # I
        J = K[r] * n("annex_gold_per_defender") if D == "Annex" else 0.0                # J
        AP = 0 if D == "Annex" else max(I - AQ, 0)                                       # AP
        AS = n("trade_signing_fee") if (civ["trade"] and civ["first"] == r) else 0.0     # AS
        if D == "Annex":
            AR = AQ + K[r] * n("annexed_garrison_join")
        else:
            AR = max(AQ - I, 0) + I * surv_share * (1 - n("garrison_left_share"))
        times = {
            "Citizens": AP / U * 60 if AP else 0.0,
            "Barracks": AP / (c["barracks"] * OUT["barracks"] * Q) * 60 if AP else 0.0,
            "Equipment": AP / (c["factory_equipment"] * OUT["factory_equipment"] * Q) * 60 if AP else 0.0,
            "Rations": AP / (c["factory_rations"] * OUT["factory_rations"] * Q) * 60 if AP else 0.0,
            "Food": AP * n("food_per_ration") / X * 60 if AP else 0.0,
            "Metal": max(AA + AP * n("metal_per_equipment"), 0) / Y * 60,
            "Fuel": max(AB + AP * n("fuel_per_equipment"), 0) / Z * 60,
            "Gold": (AC + J + AS) / W * 60,
            "Relations": (n("relations_hours_ref") * 60 * (size[civ_of[r]] / n("relations_ref_size")) ** n("relations_size_exp")
                          * ((1 - n("trade_relations_cut")) if civ["trade"] else 1) * (1 + n("raze_relations_damage") * razes))
                         if D == "Annex" else 0.0,
        }
        F = max(times.values())                                                         # F
        bottleneck = max(times, key=times.get)                                          # H
        if D == "Annex":
            G = 0.0
        else:
            ratio = I / (K[r] * adv * Nm)
            G = n("battle_k") * (I + K[r]) ** n("battle_p") * max(n("routing_floor"), (1 / max(ratio, 1 / ratio)) ** n("routing_exp"))
        E += (F + G) / 60                                                               # E
        AU = "Annex" if D == "Annex" else civ["captured"]                               # AU
        if AU == "Raze":
            razes += 1
        rows.append({"region": r, "name": reg["Name"], "method": D, "cumulative_hrs": E, "prep_min": F,
                     "battle_min": G, "bottleneck": bottleneck, "soldiers_needed": I, "garrison": K[r]})
        AR_prev, AU_prev = AR, AU
    return rows


PATHS = {
    "default": {},
    "conquer_everyone": {"Veyra Compact": {"method": "Conquer"}},
    "conquer_everyone_raze_kharn": {"Veyra Compact": {"method": "Conquer"}, "Kharn Clans": {"captured": "Raze"}},
    "annex_veyra_raze_kharn": {"Kharn Clans": {"captured": "Raze"}},
}

# The sheet's own numbers for the default path (Timeline E12:E22, revision 45).
SHEET_DEFAULT = [0.08104563826865996, 0.3958282653423117, 0.6940583323173493, 0.9841386410912831,
                 1.274218949865217, 1.5642992586391509, 1.9327226494219145, 2.47433131317202,
                 3.1089965248276967, 3.869778041425686, 5.1058354848698855]

if __name__ == "__main__":
    if "--check" in sys.argv:
        rows = timeline()
        worst = max(abs(a["cumulative_hrs"] - b) for a, b in zip(rows, SHEET_DEFAULT))
        print("default path vs sheet: worst difference %.2e h" % worst)
        sys.exit(0 if worst < 1e-9 else 1)
    if "--golden" in sys.argv:
        path = os.path.join(ROOT, "tests", "golden", "sheet_paths.csv")
        with open(path, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["path", "region", "cumulative_hrs", "prep_min", "battle_min", "bottleneck"])
            for name, o in PATHS.items():
                for row in timeline(o):
                    w.writerow([name, row["region"], "%.6f" % row["cumulative_hrs"], "%.4f" % row["prep_min"],
                                "%.4f" % row["battle_min"], row["bottleneck"]])
        print("wrote", path)
    for name, o in PATHS.items():
        rows = timeline(o)
        print("%-30s %.3f h  first capture %.2f min" % (name, rows[-1]["cumulative_hrs"], rows[0]["cumulative_hrs"] * 60))
