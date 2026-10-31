# -*- coding: utf-8 -*-
"""
黄金城 原版规则取证工具 (V5.3 配套, 仅依赖 Python 标准库)

只读 MT5 策略测试器导出的 HTML 报告(UTF-16), 复算《黄金城V5.3_逆向深挖报告.md》里的每一条规则计数。
不读取任何行情数据, 不跑回测。

用法:
    python 原版规则取证.py  原版报告.html  [复刻版报告.html]

输出:
    ① 各策略挂单有效期分布 (B=310h 规则)
    ② 同槽相邻挂单间隔 <900 秒的次数 (槽位挂单节流规则)
    ③ 亏损平仓后的重挂锚点: 挂单+900 / 平仓+900 (亏损冷却锚定规则)
    ④ 盘中过期后同一结构位是否当场重挂 (过期同位等新K线规则)
    ⑤ 替换时旧单撤销时间是否 ≥ 新单挂出时间 (先挂后删规则)
    ⑥ (给出复刻版报告时) 原版晚挂的单相对复刻版挂单时刻的价格方向 (未锁死规则 ⑦ 的证据)
"""
import sys, html.parser, datetime as dt
from collections import Counter, defaultdict

SLU = {'A': 1.5, 'B': 5.0, 'C': 1.5, 'D': 1.5, 'E': 1.4}           # 止损 ×U
TPU = {'A': 11.5, 'B': 10.5, 'C': 7.5, 'D': 12.5, 'E': 11.5}       # 止盈 ×U
TFS = {'A': 7200, 'B': 86400, 'C': 14400, 'D': 7200, 'E': 7200}    # 结构周期(秒)
BUF_B, BUF_S, UNIT = 0.1435, 0.258, 0.002                           # 买/卖缓冲 ×U, U=0.2%×Ask


class _Rows(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(); self.rows = []; self.cur = None; self.cell = None
    def handle_starttag(self, t, a):
        if t == 'tr': self.cur = []
        elif t in ('td', 'th') and self.cur is not None: self.cell = []
    def handle_endtag(self, t):
        if t in ('td', 'th') and self.cell is not None and self.cur is not None:
            self.cur.append(''.join(self.cell).strip()); self.cell = None
        elif t == 'tr' and self.cur is not None:
            self.rows.append(self.cur); self.cur = None
    def handle_data(self, d):
        if self.cell is not None: self.cell.append(d)


def _t(s): return dt.datetime.strptime(s, '%Y.%m.%d %H:%M:%S')
def _n(s):
    s = s.replace(' ', '').replace('\xa0', '')
    return float(s) if s else None


def load(path):
    """解析报告 → (挂单列表, 成交列表)。挂单附带 策略/方向/U/结构位L。"""
    raw = open(path, 'rb').read()
    txt = raw.decode('utf-16') if raw[:2] in (b'\xff\xfe', b'\xfe\xff') else raw.decode('utf-8', 'ignore')
    p = _Rows(); p.feed(txt); r = p.rows
    i0 = [i for i, x in enumerate(r) if x == ['订单']][0]
    i1 = [i for i, x in enumerate(r) if x == ['成交']][0]
    orders, deals = [], []
    for x in r[i0 + 2:i1]:
        if len(x) < 11 or x[3] not in ('buy stop', 'sell stop'): continue
        o = dict(t0=_t(x[0]), tk=int(x[1]), price=_n(x[5]), sl=_n(x[6]), tp=_n(x[7]),
                 t1=_t(x[8]) if x[8] else None, state=x[9], cmt=x[10])
        if 'Pending' in o['cmt']:
            o['s'] = o['cmt'][-1]
        else:   # 过期单注释被改写 → 用 止盈/止损 比值识别策略
            R = abs(o['tp'] - o['price']) / abs(o['price'] - o['sl'])
            cand = {'A': 23 / 3, 'B': 2.1, 'C': 5.0, 'D': 25 / 3, 'E': 115 / 14}
            o['s'] = min(cand, key=lambda k: abs(cand[k] - R))
        o['dir'] = 'B' if x[3] == 'buy stop' else 'S'
        s = o['s']; o['U'] = abs(o['tp'] - o['sl']) / (SLU[s] + TPU[s]); o['ask'] = o['U'] / UNIT
        o['L'] = o['price'] + BUF_B * o['U'] if o['dir'] == 'B' else o['price'] - BUF_S * o['U']
        orders.append(o)
    for x in r[i1 + 2:]:
        if len(x) < 13 or not x[0] or x[3] == 'balance': continue
        deals.append(dict(t=_t(x[0]), deal=int(x[1]), type=x[3], dir=x[4], price=_n(x[6]),
                          order=int(x[7]), profit=_n(x[10]), cmt=x[12]))
    _pair(orders, deals)
    return orders, deals


def _slots(orders):
    S = defaultdict(list)
    for o in orders: S[(o['s'], o['dir'])].append(o)
    for k in S: S[k].sort(key=lambda z: (z['t0'], z['tk']))
    return S


def _pair(orders, deals):
    """把出场成交配回持仓: 入场价 = 出场价 ∓ 盈亏(0.01 手, 合约 100 盎司); 同价同刻多单按槽位规则消歧。"""
    bo = {o['tk']: o for o in orders}
    ins = sorted([d for d in deals if d['dir'] == 'in'], key=lambda d: (d['t'], d['deal']))
    outs = sorted([d for d in deals if d['dir'] == 'out'], key=lambda d: (d['t'], d['deal']))
    openp, ii = [], 0
    for od in outs:
        while ii < len(ins) and (ins[ii]['t'], ins[ii]['deal']) < (od['t'], od['deal']):
            openp.append(ins[ii]); ii += 1
        pt = 'buy' if od['type'] == 'sell' else 'sell'
        est = od['price'] - od['profit'] if pt == 'buy' else od['price'] + od['profit']
        best = min((p for p in openp if p['type'] == pt), key=lambda p: abs(p['price'] - est), default=None)
        if best is None: continue
        openp.remove(best)
        o = bo.get(best['order'])
        if o: o['in'] = best; o['out'] = od
    # 同价同刻多单: 按「下一单挂出时刻」与 盈利0秒/亏损900秒 的一致性重排
    S = _slots(orders); nxt = {}
    for L in S.values():
        for i, o in enumerate(L): nxt[o['tk']] = L[i + 1]['t0'] if i + 1 < len(L) else None
    G = defaultdict(list)
    for o in orders:
        if 'in' in o: G[(o['in']['type'], round(o['in']['price'], 3), o['in']['t'])].append(o)
    import itertools
    def sc(o, od):
        n = nxt[o['tk']]
        if n is None: return 0
        d = (n - od['t']).total_seconds()
        if d < 0: return -100
        if od['profit'] >= 0: return 5 if d <= 1 else 0
        return 5 if 899 <= d <= 905 else (0 if d > 905 else -50)
    for grp in G.values():
        if len(grp) < 2 or len(grp) > 6: continue
        outs_ = [o['out'] for o in grp]
        best = max(itertools.permutations(outs_), key=lambda pm: sum(sc(o, od) for o, od in zip(grp, pm)))
        for o, od in zip(grp, best): o['out'] = od


def _barsec(t, s): return int((t - dt.datetime(1970, 1, 1)).total_seconds()) % TFS[s]


def report(path, ref=None):
    O, D = load(path)
    S = _slots(O)
    print('=' * 70); print('报告:', path); print('挂单 %d 张, 成交 %d 笔' % (len(O), sum(1 for o in O if 'out' in o)))

    print('\n① 挂单有效期(小时, 仅 expired):')
    for s in 'ABCDE':
        E = [(o['t1'] - o['t0']).total_seconds() / 3600 for o in O if o['s'] == s and o['state'] == 'expired']
        print('  %s: %s' % (s, Counter(round(e, 1) for e in E).most_common(4)))

    iv = []
    for L in S.values():
        for i in range(1, len(L)): iv.append((L[i]['t0'] - L[i - 1]['t0']).total_seconds())
    print('\n② 同槽相邻挂单间隔: 共 %d 个, <900 秒 %d 个, 恰为 900–905 秒 %d 个'
          % (len(iv), sum(v < 900 for v in iv), sum(900 <= v <= 905 for v in iv)))

    C = Counter()
    for L in S.values():
        for i, o in enumerate(L):
            if 'out' not in o or o['out']['profit'] >= 0 or i + 1 >= len(L): continue
            n = L[i + 1]['t0']; c = (n - o['out']['t']).total_seconds(); p = (n - o['t0']).total_seconds()
            if c < 0: continue
            life = (o['out']['t'] - o['t0']).total_seconds()
            an = '平仓+900' if 899 <= c <= 902 else ('挂单+900' if 899 <= p <= 902 else ('0秒' if c <= 1 else '其它'))
            C[('寿命<900' if life < 900 else '寿命≥900', an)] += 1
    print('\n③ 亏损平仓 → 下一单挂出锚点:')
    for k in sorted(C): print('  ', k, C[k])

    C = Counter()
    for (s, d), L in S.items():
        for i, o in enumerate(L):
            if o['state'] != 'expired' or i + 1 >= len(L): continue
            e = o['t1']
            if e.weekday() == 6 or (e.weekday() == 0 and e.hour < 1): continue
            nx = L[i + 1]; dl = (nx['t0'] - e).total_seconds()
            same = abs(nx['L'] - o['L']) < 0.01
            tm = '当场' if dl <= 1 else ('下根K线开盘' if _barsec(nx['t0'], s) < 5 else '更晚')
            C[('K线开盘过期' if _barsec(e, s) < 5 else 'K线中途过期', '同位' if same else '异位', tm)] += 1
    print('\n④ 工作日过期后的重挂:')
    for k in sorted(C): print('  ', k, C[k])

    C = Counter()
    for L in S.values():
        for i, o in enumerate(L):
            if o['state'] != 'canceled' or i + 1 >= len(L): continue
            dl = (o['t1'] - L[i + 1]['t0']).total_seconds()
            if abs(dl) > 5: continue
            C['撤旧晚于挂新' if dl > 0 else ('同秒' if dl == 0 else '撤旧早于挂新')] += 1
    print('\n⑤ 替换顺序:', dict(C))

    if ref:
        R, _ = load(ref); SR = _slots(R)
        C = Counter()
        for k, L in S.items():
            V = SR.get(k, [])
            for j, o in enumerate(L):
                if j > 0 and 'out' in L[j - 1]: continue      # 只看非平仓触发的挂单(过期/替换/首挂)
                y = None
                for z in V:
                    if abs(z['L'] - o['L']) < 0.01 and z['t0'] <= o['t0'] and (o['t0'] - z['t0']).total_seconds() < 3 * 86400:
                        y = z
                if y is None or (o['t0'] - y['t0']).total_seconds() <= 1: continue
                dp = o['ask'] - y['ask']
                C[(k[1], '原版挂时价更高' if dp > 0.05 else ('更低' if dp < -0.05 else '持平'))] += 1
        print('\n⑥ 非平仓触发的挂单, 原版比复刻版晚挂同一结构位时的价格方向 (B=买单 S=卖单):')
        for k in sorted(C): print('  ', k, C[k])


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    report(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
