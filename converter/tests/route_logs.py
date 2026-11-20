"""
覚醒編零式 4 層（タイタン）の形を真似た記録ログを作る（スレッド #9 のテスト用。実データが無いため）
  共通 → 車型ブロック or 人型ブロック → 共通（岩盤崩落〜）→ 逆の形態のブロック → フェーズ 2（マキシタイタン）
  人型ブロックの最後はライト／レフト・ランドスライドのランダム
"""
import csv
import os

BOSS_CID, BOSS_ID = 9001, 1073750001
HEAD = ['t', 'kind', 'entity_id', 'contentid', 'base_id', 'max_hp', 'action_id', 'cast', 'target_id', 'v1', 'v2', 'name']
COMMON1 = [(5, 1001), (15, 1002), (25, 1003), (35, 1004), (45, 1005)]       # ①〜⑤
CAR = [(0, 7001), (8, 7002), (16, 7003)]                                       # フォールトゾーン → … （長さ 20 秒）
HUMAN = [(0, 7101), (10, 7102), (18, 7103), (26, None)]                        # メガ・ランドスライド → … （長さ 32 秒）
MID = [(0, 2001), (10, 2002), (20, 2003), (30, 2004), (40, 2005)]              # 岩盤崩落〜（長さ 48 秒）
P2 = [(0, 3001), (12, 3002), (25, 3003)]


def make_pull(path, car_first: bool, lr: int = 7104):
    rows = [dict(t=-9.0, kind='appear', entity_id=BOSS_ID, contentid=BOSS_CID, max_hp=1000000, v2=1, name='タイタン'),
            dict(t=-9.0, kind='targetable', entity_id=BOSS_ID, contentid=BOSS_CID, max_hp=1000000, v1=1, name='タイタン'),
            dict(t=0.0, kind='combat_start', entity_id=BOSS_ID, contentid=BOSS_CID)]
    casts = list(COMMON1)
    t = 55.0
    order = [(CAR, 20, None), (HUMAN, 32, lr)] if car_first else [(HUMAN, 32, lr), (CAR, 20, None)]
    blk, ln, x = order[0]
    casts += [(t + dt, a if a else x) for dt, a in blk]
    t += ln
    casts += [(t + dt, a) for dt, a in MID]
    t += 48
    blk, ln, x = order[1]
    casts += [(t + dt, a if a else x) for dt, a in blk]
    t += ln
    casts += [(t + 6 + dt, a) for dt, a in P2]
    end = t + 6 + 40
    for ct, a in casts:
        rows.append(dict(t=round(ct, 1), kind='cast_start', entity_id=BOSS_ID, contentid=BOSS_CID, action_id=a, cast=3.0,
                         target_id=BOSS_ID, name='a%d' % a))
        rows.append(dict(t=round(ct + 3.0, 1), kind='cast_end', entity_id=BOSS_ID, contentid=BOSS_CID, action_id=a,
                         target_id=BOSS_ID, name='a%d' % a))
    hp = 1000000
    tt = 1.0
    while tt < end:
        hp -= 3000
        rows.append(dict(t=round(tt, 1), kind='hp', entity_id=BOSS_ID, contentid=BOSS_CID, max_hp=1000000,
                         v1=round(hp / 10000, 1), v2=hp, name='タイタン'))
        tt += 2.0
    rows.append(dict(t=round(end, 1), kind='wipe', entity_id=BOSS_ID, contentid=BOSS_CID))
    rows.sort(key=lambda r: r['t'])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, HEAD)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, '') for k in HEAD})
    return path


def make_route_logs(folder):
    """ルート A（車型が先）2 プル・ルート B（人型が先）2 プル。ライト／レフトはプルでばらばら"""
    return [make_pull(os.path.join(folder, '20261116_10%02d00.csv' % i), car, lr)
            for i, (car, lr) in enumerate(PULLS)]


PULLS = [(True, 7104), (False, 7105), (True, 7105), (False, 7104)]   # （車型が先か, ライト／レフト）


# ---------------------------------------------------------------------
# 火力でフェーズの長さが変わる戦闘（極エヌオーの雑魚フェーズの形）
#   前半：ボスが 10 秒ごとに詠唱（4001〜）。HP 60% でボスがターゲット不可になり、雑魚 3 体（9102）が出る
#   雑魚フェーズ：雑魚が 5001（+4 秒）・5002（+14 秒）・5003（+24 秒）…。全部倒すとボスがターゲット可に戻る
#   後半：ボスが 6001（+3 秒）・6002（+13 秒）・6003（+23 秒）
#   rate（%/秒）と kill（雑魚を倒すのにかかる秒数）がプルで違う
DPS_BOSS, DPS_BOSS_ID = 9101, 1073751001
DPS_ADD, DPS_ADD_IDS = 9102, (1073751101, 1073751102, 1073751103)
DPS_PULLS = [(0.50, 30.0), (0.60, 25.0), (0.75, 18.0)]


def make_dps_pull(path, rate, kill):
    rows = [dict(t=-9.0, kind='appear', entity_id=DPS_BOSS_ID, contentid=DPS_BOSS, max_hp=1000000, v2=1, name='エヌオー'),
            dict(t=-9.0, kind='targetable', entity_id=DPS_BOSS_ID, contentid=DPS_BOSS, max_hp=1000000, v1=1, name='エヌオー'),
            dict(t=0.0, kind='combat_start', entity_id=DPS_BOSS_ID, contentid=DPS_BOSS)]
    push = 40.0 / rate                    # HP 100% → 60%
    hp_rows = []
    t = 1.0
    while t < push:
        hp_rows.append((t, DPS_BOSS_ID, DPS_BOSS, 1000000 - int(round(rate * t * 10000))))
        t += 1.0
    hp_rows.append((round(push, 1), DPS_BOSS_ID, DPS_BOSS, 600000))
    casts = [(dt, DPS_BOSS_ID, DPS_BOSS, 4001 + i) for i, dt in enumerate(range(5, 200, 10)) if dt + 3 < push]
    rows.append(dict(t=round(push + 0.3, 1), kind='targetable', entity_id=DPS_BOSS_ID, contentid=DPS_BOSS, v1=0, name='エヌオー'))
    for aid in DPS_ADD_IDS:
        rows.append(dict(t=round(push + 1.0, 1), kind='appear', entity_id=aid, contentid=DPS_ADD, max_hp=100000, v2=1, name='光の兆し'))
        rows.append(dict(t=round(push + 1.0, 1), kind='targetable', entity_id=aid, contentid=DPS_ADD, v1=1, name='光の兆し'))
    adds_end = push + 1.0 + kill
    for i, dt in enumerate(range(4, 200, 10)):
        if push + 1.0 + dt + 3 < adds_end:
            casts.append((push + 1.0 + dt, DPS_ADD_IDS[0], DPS_ADD, 5001 + i))
    t = push + 2.0
    while t < adds_end:
        for aid in DPS_ADD_IDS:
            hp_rows.append((round(t, 1), aid, DPS_ADD, max(1, int(100000 * (1 - (t - push - 1.0) / kill)))))
        t += 1.0
    for aid in DPS_ADD_IDS:
        hp_rows.append((round(adds_end, 1), aid, DPS_ADD, 0))
        rows.append(dict(t=round(adds_end + 0.2, 1), kind='disappear', entity_id=aid, contentid=DPS_ADD, name='光の兆し'))
    back = adds_end + 1.0
    rows.append(dict(t=round(back, 1), kind='targetable', entity_id=DPS_BOSS_ID, contentid=DPS_BOSS, v1=1, name='エヌオー'))
    for i, dt in enumerate((3, 13, 23)):
        casts.append((back + dt, DPS_BOSS_ID, DPS_BOSS, 6001 + i))
    end = back + 30
    t = back + 1.0
    while t < end:
        hp_rows.append((round(t, 1), DPS_BOSS_ID, DPS_BOSS, 600000 - int(round(rate * (t - back) * 10000))))
        t += 1.0
    for ct, eid, cid, a in casts:
        rows.append(dict(t=round(ct, 1), kind='cast_start', entity_id=eid, contentid=cid, action_id=a, cast=3.0,
                         target_id=eid, name='a%d' % a))
        rows.append(dict(t=round(ct + 3.0, 1), kind='cast_end', entity_id=eid, contentid=cid, action_id=a,
                         target_id=eid, name='a%d' % a))
    for ht, eid, cid, hp in hp_rows:
        mx = 1000000 if cid == DPS_BOSS else 100000
        rows.append(dict(t=ht, kind='hp', entity_id=eid, contentid=cid, max_hp=mx, v1=round(hp * 100 / mx, 1), v2=hp,
                         name='x'))
    rows.append(dict(t=round(end, 1), kind='wipe', entity_id=DPS_BOSS_ID, contentid=DPS_BOSS))
    rows.sort(key=lambda r: r['t'])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, HEAD)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, '') for k in HEAD})
    return path


def make_dps_logs(folder):
    return [make_dps_pull(os.path.join(folder, '20261116_11%02d00.csv' % i), rate, kill)
            for i, (rate, kill) in enumerate(DPS_PULLS)]
