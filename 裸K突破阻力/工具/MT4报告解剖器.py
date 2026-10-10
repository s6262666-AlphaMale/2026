#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MT4 策略测试报告解剖器 v1.0  (配合 裸K突破阻力 复刻版 V1.x; 其他 EA 的报告也能用, 只是参数没有中文名)

做什么:
  读取 MT4 回测报告(.htm), 按"空仓 → 空仓"切出每一个篮子, 用每笔成交价反推篮子的浮动盈亏路径,
  回答三个问题: 最大回撤来自哪一篮? 那一刻多空各几单、净敞口多少手? 两个设置从哪一笔开始走上不同的路?

用法(Windows 命令行, 需 Python 3.8+, 无第三方依赖):
  python MT4报告解剖器.py 报告.htm                       单份解剖
  python MT4报告解剖器.py 设置1.htm 设置2.htm             两份对比: 参数差异 + 第一处分叉 + 逐日对照
  python MT4报告解剖器.py 设置1.htm --day 2026.08.17      打印某一天的逐笔时间线
  python MT4报告解剖器.py 设置1.htm --top 10 --csv 输出目录  浮亏最深前10篮, 并导出篮子/逐日 CSV
  可选: --contract 100 (合约大小, 默认按成交盈亏自动反推)  --spread 0.26 (点差价格, 默认读报告头)

口径(务必读):
  ① 只用报告里的成交记录, 不读任何外部行情。
  ② 浮亏是"成交时刻采样": 两笔成交之间价格继续逆向时看不到, 所以篮子真实最深浮亏 ≥ 采样值。
     报告头的"最大亏损"由 MT4 逐 tick 按净值统计, 才是真实最深点; 本工具同时列出两者并给出覆盖率。
  ③ 买单开仓价 = Ask、卖单开仓价 = Bid, 平仓相反; 点差取报告头"点差 N" × 最小价位(固定点差回测成立)。
  ④ 未计持仓中的库存费; 已平仓盈亏直接取报告"余额"列。
"""
import sys, os, re, html, argparse, statistics, csv
from collections import OrderedDict

CN = {
    'InpLots': '每单手数',
    'InpTargetMoney': '整体止盈金额',
    'InpMaxOrders': '最大持仓单数',
    'InpCooldownSec': '整体平仓后冷却秒数',
    'InpWindowMin': '时段开仓窗口',
    'InpSignalDist': '[P3]方向K线实体触发距离',
    'InpRefPeriodMin': '方向参考K线周期',
    'InpRefOffsetMin': '方向K线起点偏移',
    'InpBreakDist': '突破加仓距离',
    'InpResistDist': '阻力加仓距离',
    'InpSideMode': '加仓距离计价口径',
    'InpBreakNeedSignal': '突破加仓也要求方向信号同向',
    'InpTimeShiftHours': '本平台服务器时间减DLS原版服务器时间',
    'InpReverseMode': '[P1]窗口内反向裸K处理方式',
    'InpReverseScope': '[P1]反向持仓判定范围',
    'InpReverseDist': '[P1]反向裸K实体阈值',
    'InpRefMinAgeMin': '[P1]首单要求方向K线已走过N分钟',
    'InpTrailPct': '[P2]移动锁利回撤比例%',
    'InpTrailMinGive': '[P2]移动锁利最小回撤金额',
    'InpTrailAllowAdd': '[P2]移动锁利期间继续突破加仓',
    'InpMoneyAutoScale': '[P6]金额参数按敞口自动缩放',
    'InpDailyTarget': '[P7]每日目标',
    'InpCapitalGuard': '[P8]实盘净值低于"建议最低净值"时停开新篮',
    'InpDiagLog': '[D1]开单诊断日志',
    'InpS1On': '时段1 启用',
    'InpS1Time': '时段1 开始时间',
    'InpS1Magic': '时段1 魔术号',
    'InpS2On': '时段2 启用',
    'InpS2Time': '时段2 开始时间',
    'InpS2Magic': '时段2 魔术号',
    'InpS3On': '时段3 启用',
    'InpS3Time': '时段3 开始时间',
    'InpS3Magic': '时段3 魔术号',
    'InpS4On': '时段4 启用',
    'InpS4Time': '时段4 开始时间',
    'InpS4Magic': '时段4 魔术号',
    'InpS5On': '时段5 启用',
    'InpS5Time': '时段5 开始时间',
    'InpS5Magic': '时段5 魔术号',
    'InpTagK': '首单注释前缀',
    'InpTagBreak': '突破加仓注释前缀',
    'InpTagResist': '阻力加仓注释前缀',
    'InpTagVer': '版本标记',
    'InpTagMid': '魔术号后标记位',
    'InpSlippagePrice': '最大滑点',
    'InpRetry': '下单/平仓失败重试次数',
    'InpRetryDelayMs': '重试间隔',
    'InpScope': '整体盈亏/全平/持仓上限的统计范围',
    'InpSlotLock': '多图表时段占用锁',
    'InpVerboseLog': '详细日志',
    'InpMaxSpread': '[P5]开仓最大点差',
    'InpStopLossMoney': '整体浮亏止损金额',
    'InpEquityStopPct': '净值回撤止损%',
    'InpStopPauseHours': '[P4]附加风控止损触发后暂停开仓小时数',
    'InpFridayClose': '周五定时全平并停开至下周',
    'InpFridayTime': '周五全平时间',
    'InpUiEnable': '启用工业级UI面板',
    'InpUiWidth': 'UI面板宽度',
    'InpUiLogLines': 'UI面板日志显示行数',
    'InpUiButtons': '启用UI面板人工按钮',
    'InpUiStatsAll': '面板已平统计:true=本EA全部历史 false=仅本次启动后',
    'InpPipMode': '点值口径:0=自适应',
    'InpManualMagic': '人工单魔术号',
    'InpManualMaxLot': '人工单单笔最大手数',
    'InpRcEnable': '启用遥控指令单',
    'InpRcMagic': '指令单魔术号',
    'InpRcPrice': '指令单挂单价位',
    'InpRcLots': '指令单手数',
    'InpRcStandby': '待机码',
    'InpRcWriteBack': '执行后写回待机码',
    'InpRcAutoPlace': '指令单不存在时自动挂出',
    'InpRcPersist': '停开/保本等遥控状态跨重启保持',
    'InpRcBeMoney': '遥控"止盈移到保本":整体浮盈≥该值即全平',
    'InpRcCode1': '码位1 指令码',
    'InpRcAct1': '码位1 动作',
    'InpRcCode2': '码位2 指令码',
    'InpRcAct2': '码位2 动作',
    'InpRcCode3': '码位3 指令码',
    'InpRcAct3': '码位3 动作',
    'InpRcCode4': '码位4 指令码',
    'InpRcAct4': '码位4 动作',
    'InpRcCode5': '码位5 指令码',
    'InpRcAct5': '码位5 动作',
    'InpRcCode6': '码位6 指令码',
    'InpRcAct6': '码位6 动作',
    'InpShowPanel': '显示信息面板',
    'InpPanelCorner': '面板位置',
    'InpPanelX': '面板横向偏移',
    'InpPanelY': '面板纵向偏移',
    'InpFontSize': '面板字号',
    'InpFontName': '面板字体',
    'InpColorBg': '面板背景色',
    'InpColorText': '面板文字色',
    'InpColorBuy': '多单颜色',
    'InpColorSell': '空单颜色',
    'InpColorWarn': '提示颜色',
}


def cn(name):
    return CN.get(name, '')

# ---------------------------------------------------------------- 读取与解析
def read_text(path):
    b = open(path, 'rb').read()
    if b[:2] in (b'\xff\xfe', b'\xfe\xff'):
        return b.decode('utf-16')
    for enc in ('utf-8', 'gbk'):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            pass
    return b.decode('gbk', errors='replace')

def clean(s):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', s))).strip()

CLOSE_TYPES = ('close', 's/l', 't/p', 'close at stop', 'close by')

def parse_report(path):
    t = read_text(path)
    trs = re.findall(r'<tr[^>]*>(.*?)</tr>', t, flags=re.S | re.I)
    rows, head_txt = [], []
    for tr in trs:
        cells = [clean(c) for c in re.findall(r'<td[^>]*>(.*?)</td>', tr, flags=re.S | re.I)]
        if len(cells) >= 9 and re.match(r'^\d+$', cells[0]) and re.match(r'\d{4}\.\d\d\.\d\d', cells[1]):
            def num(x):
                try:
                    return float(x.replace(' ', ''))
                except ValueError:
                    return None
            rows.append(dict(n=int(cells[0]), t=cells[1], typ=cells[2].lower(), tk=int(cells[3]),
                             lots=num(cells[4]), px=num(cells[5]), pl=num(cells[8]),
                             bal=num(cells[9]) if len(cells) > 9 else None))
        elif not rows:
            head_txt.append(' | '.join(cells))
    head = ' || '.join(head_txt)
    info = OrderedDict()
    def grab(key, pats, conv=float):
        for p in pats:
            m = re.search(p, head)
            if m:
                try:
                    info[key] = conv(m.group(1).replace(' ', ''))
                except ValueError:
                    pass
                return
    m = re.search(r'<title>(.*?)</title>', t, flags=re.S | re.I)
    info['标题'] = re.sub(r'^(Strategy Tester|策略测试)\s*:\s*', '', clean(m.group(1))) if m else ''
    grab('品种', [r'交易品种 \| (\S+)', r'Symbol \| (\S+)'], str)
    grab('起始资金', [r'起始资金 \| ([\d. ]+)', r'Initial deposit \| ([\d. ]+)'])
    grab('点差点数', [r'点差 \| (?:当前 \()?(\d+)', r'Spread \| (?:Current \()?(\d+)'])
    grab('净利', [r'总净盈利 \| (-?[\d. ]+)', r'Total net profit \| (-?[\d. ]+)'])
    grab('绝对亏损', [r'绝对亏损 \| ([\d. ]+)', r'Absolute drawdown \| ([\d. ]+)'])
    grab('最大亏损', [r'最大亏损 \| ([\d. ]+)', r'Maximal drawdown \| ([\d. ]+)'])
    grab('最大亏损%', [r'最大亏损 \| [\d. ]+ \(([\d.]+)%\)', r'Maximal drawdown \| [\d. ]+ \(([\d.]+)%\)'])
    grab('交易单总计', [r'交易单总计 \| (\d+)', r'Total trades \| (\d+)'], int)
    m = re.search(r'(?:时间周期|Period) \| (.*?) \|', head)
    info['周期'] = m.group(1) if m else ''
    params = OrderedDict()
    m = re.search(r'(?:参数|Parameters) \| (.*?)(?: \|\| |$)', head)
    if m:
        for k, v in re.findall(r'(\w+)=("[^"]*"|[^;]*);', m.group(1) + ';'):
            params[k.strip()] = v.strip().strip('"')
    return info, params, rows

# ---------------------------------------------------------------- 口径推断
def infer_point(rows):
    d = 0
    for r in rows[:400]:
        if r['px'] is None:
            continue
        s = ('%.6f' % r['px']).rstrip('0')
        d = max(d, len(s.split('.')[1]) if '.' in s else 0)
    return 10 ** (-d) if d else 1.0

def infer_contract(rows):
    op, est = {}, []
    for r in rows:
        if r['typ'] in ('buy', 'sell'):
            op[r['tk']] = r
        elif r['typ'] in CLOSE_TYPES and r['tk'] in op and r['pl'] is not None:
            o = op[r['tk']]
            d = (r['px'] - o['px']) if o['typ'] == 'buy' else (o['px'] - r['px'])
            if abs(d) >= 0.5 and o['lots']:
                est.append(r['pl'] / (d * o['lots']))
    if not est:
        return 100.0
    c = statistics.median(est)
    for nice in (1, 10, 100, 1000, 10000, 100000):
        if abs(c - nice) / nice < 0.03:
            return float(nice)
    return round(c, 2)

# ---------------------------------------------------------------- 重建
def rebuild(info, rows, spread, cs):
    dep = info.get('起始资金', 0.0)
    pos, bal = OrderedDict(), dep
    peak, mdd, mdd_at, mineq, mineq_at = dep, 0.0, None, dep, None
    peak_at = None
    baskets, cur, daily, events = [], None, OrderedDict(), []
    def floating(bid):
        f = 0.0
        for side, op, lots in pos.values():
            f += ((bid - op) if side == 'buy' else (op - (bid + spread))) * cs * lots
        return f
    for r in rows:
        typ = r['typ']
        if typ in ('buy', 'sell'):
            bid = r['px'] - spread if typ == 'buy' else r['px']
            if cur is None:
                cur = dict(t0=r['t'], bal0=bal, n=0, nb=0, ns=0, maxn=0, maxlots=0.0,
                           worst=0.0, worst_t=r['t'], worst_bid=bid, worst_b=0, worst_s=0, worst_net=0.0)
            pos[r['tk']] = (typ, r['px'], r['lots'])
            cur['n'] += 1
            cur['nb' if typ == 'buy' else 'ns'] += 1
        elif typ in CLOSE_TYPES:
            if r['tk'] not in pos:
                continue
            side = pos[r['tk']][0]
            bid = r['px'] if side == 'buy' else r['px'] - spread
            del pos[r['tk']]
            bal = r['bal'] if r['bal'] is not None else bal + (r['pl'] or 0.0)
            day = r['t'][:10]
            daily.setdefault(day, dict(pl=0.0, n=0, baskets=0))
            daily[day]['pl'] += (r['pl'] or 0.0)
            daily[day]['n'] += 1
        else:
            continue
        eq = bal + floating(bid)
        nb = sum(1 for v in pos.values() if v[0] == 'buy')
        ns = len(pos) - nb
        lb = sum(v[2] for v in pos.values() if v[0] == 'buy')
        ls = sum(v[2] for v in pos.values() if v[0] == 'sell')
        events.append((r['t'], typ, r['tk'], r['px'], bid, nb, ns, eq, (eq - cur['bal0']) if cur else 0.0))
        if cur is not None:
            cur['maxn'] = max(cur['maxn'], len(pos))
            cur['maxlots'] = max(cur['maxlots'], lb + ls)
            rel = eq - cur['bal0']
            if rel < cur['worst']:
                cur.update(worst=rel, worst_t=r['t'], worst_bid=bid, worst_b=nb, worst_s=ns, worst_net=lb - ls)
        if eq > peak:
            peak, peak_at = eq, r['t']
        if peak - eq > mdd:
            mdd, mdd_at = peak - eq, (peak_at, peak, r['t'], eq)
        if eq < mineq:
            mineq, mineq_at = eq, r['t']
        if typ in CLOSE_TYPES and not pos and cur is not None:
            cur['t1'] = r['t']
            cur['pl'] = bal - cur['bal0']
            baskets.append(cur)
            daily[r['t'][:10]]['baskets'] += 1
            cur = None
    if cur is not None:
        cur['t1'] = '(未平)'
        cur['pl'] = None
        baskets.append(cur)
    return dict(baskets=baskets, daily=daily, events=events, mdd=mdd, mdd_at=mdd_at,
                mineq=mineq, mineq_at=mineq_at, final=bal)

def minutes(t0, t1):
    import datetime as dt
    try:
        a = dt.datetime.strptime(t0, '%Y.%m.%d %H:%M')
        b = dt.datetime.strptime(t1, '%Y.%m.%d %H:%M')
        return (b - a).total_seconds() / 60.0
    except ValueError:
        return float('nan')

def fmt_dur(m):
    if m != m:
        return '--'
    return '%d时%02d分' % (int(m // 60), int(m % 60)) if m >= 60 else '%d分' % int(m)

# ---------------------------------------------------------------- 输出
KEY_PARAMS = ['InpLots', 'InpSignalDist', 'InpBreakDist', 'InpResistDist', 'InpBreakNeedSignal', 'InpTargetMoney',
              'InpTrailPct', 'InpReverseMode', 'InpReverseScope', 'InpMaxOrders', 'InpMaxSpread', 'InpStopLossMoney',
              'InpMoneyAutoScale', 'InpCapitalGuard']

def show_one(path, args):
    info, params, rows = parse_report(path)
    if not rows:
        print('未在报告中找到成交记录:', path)
        return None
    point = infer_point(rows)
    spread = args.spread if args.spread is not None else info.get('点差点数', 0) * point
    cs = args.contract if args.contract is not None else infer_contract(rows)
    R = rebuild(info, rows, spread, cs)
    B = R['baskets']
    print('═' * 100)
    print('报告:', os.path.basename(path))
    print('EA: %s | 品种 %s | %s' % (info.get('标题', ''), info.get('品种', ''), info.get('周期', '')))
    print('起始资金 %.2f | 点差 %s点 = %.3f | 最小价位 %g | 合约 %g%s' % (
        info.get('起始资金', 0), int(info.get('点差点数', 0)), spread, point, cs,
        '' if args.contract is not None else '(按成交盈亏反推)'))
    kp = [k for k in KEY_PARAMS if k in params]
    if kp:
        print('关键参数:')
        for k in kp:
            print('   %-20s %-10s %s' % (k, params[k], cn(k)))
    md, mdp = info.get('最大亏损'), info.get('最大亏损%')
    print('报告头(逐tick按净值): 净利 %s | 最大亏损 %s (%s%%) | 绝对亏损 %s (最低净值 %.2f)' % (
        info.get('净利'), md, mdp, info.get('绝对亏损'), info.get('起始资金', 0) - (info.get('绝对亏损') or 0)))
    a = R['mdd_at']
    cover = (R['mdd'] / md * 100) if md else float('nan')
    if a:
        print('成交采样(本工具):   最大回撤 %.2f (峰 %.2f @%s → 谷 %.2f @%s) | 覆盖率 %.0f%%' % (
            R['mdd'], a[1], a[0], a[3], a[2], cover))
    if cover == cover and cover < 80:
        print('   ↳ 覆盖率偏低: 真实谷底出现在两笔成交之间(价格继续逆向时没有开平仓), 实际比采样更深。')
    nloss = sum(1 for b in B if b['pl'] is not None and b['pl'] < 0)
    print('篮子 %d 个 | 平均 %.1f 单 | 最多 %d 单 | 单篮持仓峰值 %.2f 手 | 亏损篮 %d | 未平 %d' % (
        len(B), sum(b['n'] for b in B) / max(1, len(B)), max(b['n'] for b in B), max(b['maxlots'] for b in B),
        nloss, sum(1 for b in B if b['pl'] is None)))
    days = R['daily']
    if days:
        pls = [d['pl'] for d in days.values()]
        print('交易日 %d | 日均已实现 %.2f | 最差日 %.2f | 最好日 %.2f | 日均平仓单数 %.1f' % (
            len(pls), sum(pls) / len(pls), min(pls), max(pls), sum(d['n'] for d in days.values()) / len(pls)))
    print('-' * 100)
    print('浮亏最深的 %d 篮(成交采样; 净敞口 = 多单手数 - 空单手数, 正=净多):' % args.top)
    print('  %-16s %-11s %-9s %-12s %-8s %-30s %s' % ('开始', '结束', '时长', '单数(多/空)', '峰值手', '采样最深(时刻 | 多/空 | 净敞口)', '结果'))
    for b in sorted(B, key=lambda b: b['worst'])[:args.top]:
        print('  %-16s %-11s %-9s %3d(%2d/%2d)   %6.2f  %9.0f (%s | %d/%d | %+.2f手)  %s' % (
            b['t0'], b['t1'][5:] if b['t1'] != '(未平)' else b['t1'], fmt_dur(minutes(b['t0'], b['t1'])),
            b['n'], b['nb'], b['ns'], b['maxlots'], b['worst'], b['worst_t'][5:], b['worst_b'], b['worst_s'],
            b['worst_net'], ('%+.2f' % b['pl']) if b['pl'] is not None else '未平'))
    if a:
        hit = [b for b in B if b['t0'] <= a[2] <= (b['t1'] if b['t1'] != '(未平)' else '9999')]
        if hit:
            b = hit[0]
            print('最大回撤谷底落在篮子: %s → %s (%d单, 多%d/空%d, 峰值%.2f手)' % (b['t0'], b['t1'], b['n'], b['nb'], b['ns'], b['maxlots']))
    print('-' * 100)
    print('逐日:  日期        篮子  平仓单   已实现')
    for d, v in days.items():
        print('       %s  %3d   %4d   %10.2f' % (d, v['baskets'], v['n'], v['pl']))
    if args.day:
        print('-' * 100)
        print('逐笔时间线 %s (篮子权益 = 本篮开始以来 已实现+浮动):' % args.day)
        last = None
        for t, typ, tk, px, bid, nb, ns, eq, rel in R['events']:
            if not t.startswith(args.day):
                continue
            if typ in CLOSE_TYPES:
                if last == t:
                    continue
                last = t
                print('  %s 全平(首笔#%d) Bid≈%.2f  剩 多%d空%d  篮子权益 %+.0f' % (t[11:], tk, bid, nb, ns, rel))
                continue
            last = None
            print('  %s %s #%-5d @%.3f Bid≈%.2f  持仓 多%d空%d  篮子权益 %+.0f' % (
                t[11:], '开多' if typ == 'buy' else '开空', tk, px, bid, nb, ns, rel))
    if args.csv:
        os.makedirs(args.csv, exist_ok=True)
        stem = os.path.splitext(os.path.basename(path))[0]
        with open(os.path.join(args.csv, stem + '_篮子.csv'), 'w', newline='', encoding='utf-8-sig') as f:
            w = csv.writer(f)
            w.writerow(['开始', '结束', '时长分', '单数', '多', '空', '同时持仓峰值单', '峰值手数', '采样最深浮亏', '最深时刻',
                        '最深时多单', '最深时空单', '最深时净敞口手', '篮子盈亏'])
            for b in B:
                w.writerow([b['t0'], b['t1'], round(minutes(b['t0'], b['t1']), 1), b['n'], b['nb'], b['ns'], b['maxn'],
                            round(b['maxlots'], 2), round(b['worst'], 2), b['worst_t'], b['worst_b'], b['worst_s'],
                            round(b['worst_net'], 2), '' if b['pl'] is None else round(b['pl'], 2)])
        with open(os.path.join(args.csv, stem + '_逐日.csv'), 'w', newline='', encoding='utf-8-sig') as f:
            w = csv.writer(f)
            w.writerow(['日期', '平仓篮子', '平仓单数', '已实现'])
            for d, v in days.items():
                w.writerow([d, v['baskets'], v['n'], round(v['pl'], 2)])
        print('CSV 已导出到:', os.path.abspath(args.csv))
    return dict(info=info, params=params, rows=rows, R=R)

def compare(p1, p2, A, B):
    print('═' * 100)
    print('对比: [1] %s  vs  [2] %s' % (os.path.basename(p1), os.path.basename(p2)))
    diff = [k for k in A['params'] if k in B['params'] and A['params'][k] != B['params'][k]]
    print('参数差异 %d 项:' % len(diff))
    for k in diff:
        print('   %-20s [1]=%-10s [2]=%-10s %s' % (k, A['params'][k], B['params'][k], cn(k)))
    oa = [(r['t'], r['typ'], r['px']) for r in A['rows'] if r['typ'] in ('buy', 'sell')]
    ob = [(r['t'], r['typ'], r['px']) for r in B['rows'] if r['typ'] in ('buy', 'sell')]
    i = 0
    while i < min(len(oa), len(ob)) and oa[i] == ob[i]:
        i += 1
    la = A['params'].get('InpLots'); lb = B['params'].get('InpLots')
    if i == len(oa) == len(ob):
        print('开仓序列: 两份报告 %d 笔开仓逐笔相同(时间/方向/价格) → 上述参数差异在本段历史上没有改变任何一笔开仓。' % len(oa))
        if la and lb and la != lb:
            print('   手数 %s vs %s: 盈亏应按手数比例缩放, 余下差异只来自平仓贴线的舍入。' % (la, lb))
    else:
        print('开仓序列: 前 %d 笔相同, 第 %d 笔开始分叉:' % (i, i + 1))
        for tag, seq in (('[1]', oa), ('[2]', ob)):
            seg = seq[max(0, i - 2):i + 3]
            print('   %s ' % tag + ' | '.join('%s %s@%.3f' % (t[5:], '多' if ty == 'buy' else '空', px) for t, ty, px in seg))
    da, db = A['R']['daily'], B['R']['daily']
    print('逐日已实现对照:   日期        [1]          [2]        差([1]-[2])')
    for d in sorted(set(da) | set(db)):
        x = da.get(d, {}).get('pl', 0.0); y = db.get(d, {}).get('pl', 0.0)
        print('                  %s %10.2f  %10.2f  %10.2f' % (d, x, y, x - y))

def main():
    ap = argparse.ArgumentParser(description='MT4 策略测试报告解剖器(篮子浮亏重建 / 两份报告对比)')
    ap.add_argument('reports', nargs='+', help='一份或两份 MT4 回测报告 .htm')
    ap.add_argument('--top', type=int, default=8, help='列出浮亏最深的前 N 篮(默认 8)')
    ap.add_argument('--day', default=None, help='打印某天逐笔时间线, 例如 2026.08.17')
    ap.add_argument('--csv', default=None, help='把篮子明细与逐日数据导出到该目录')
    ap.add_argument('--contract', type=float, default=None, help='合约大小(默认按成交盈亏自动反推)')
    ap.add_argument('--spread', type=float, default=None, help='点差(价格单位, 默认 报告头点差点数×最小价位)')
    args = ap.parse_args()
    if len(args.reports) > 2:
        ap.error('最多两份报告')
    res = [show_one(p, args) for p in args.reports]
    if len(res) == 2 and all(res):
        compare(args.reports[0], args.reports[1], res[0], res[1])

if __name__ == '__main__':
    main()
