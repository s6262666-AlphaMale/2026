//+------------------------------------------------------------------+
//|                                     黄金城2.0_复刻版V5.3.mq5     |
//|   Gold House 2.0 行为学复刻 · V5.3 (2024+2025-26 原版报告逐单对账)  |
//|  V2 占槽/冷却/追踪三铁律 → V3 事件驱动结构位状态机 →             |
//|  V4 双侧臂+B专属窗 → V5 B卖侧去自举 · D卖臂4 · E买臂5 →          |
//|  V5.1 周日开盘放行 · 冷却同步判定 · 追踪重标定 · B回归最近位 ·   |
//|       D买臂5 · E买臂3 · OnTester复刻 · 接入四大模块 →            |
//|  V5.2 U=0.2%×Ask · 缓冲0.1435/0.258 · 非对称枢轴(左/右臂) ·      |
//|       追踪按「新极值」重算(买跟Bid/卖跟Ask) · A追踪启动0.6U →     |
//|  V5.3 B有效期310h · 槽位15分钟挂单节流 · 亏损冷却锚定 ·          |
//|       过期同位等新K线 · 先挂新单再删旧单 · 左臂历史截断           |
//+------------------------------------------------------------------+
//  V5.3 修订依据 —— 三份原版 MT5 报告(2024 全年 704 笔 / 2025.01–2026.10 1771 笔)与 V5.2 同设置报告
//  逐单对账(只用报告本身, 未用 GC 数据)。每条规则都给出原版样本中的命中/违例计数, 默认值 = 原版行为,
//  每条规则均有独立开关(见「V5.3 原版规则」参数区), 全部关掉即回到 V5.2 行为, 方便你 A/B 回测追溯。
//  ① B 挂单有效期 = 310 小时(不是 336): 2025-26 年 35 张、2024 年 20 张非周末到期单精确 310h;
//     周日开盘挂出的单 +310h 落在周六休市, 周日开盘才登记过期, 报告里显示成 336h —— 旧版误读于此。
//  ② 槽位挂单节流: 同一「策略×方向」相邻两次挂单(含择近替换)间隔恒 ≥ 15 分钟(=Inp_SLCooldownMin)。
//     2025-26: 4198/4201(另 3 例为同秒重复记录), 2024: 1625/1625 零违例; V5.2 有 23 次违例。
//  ③ 亏损冷却锚定: 亏损单「挂单→平仓」寿命 <15 分钟时, 下一单在「上次挂单 +15 分钟」挂出(46/58),
//     不再按平仓时刻追加 15 分钟; 寿命 ≥15 分钟才按「平仓 +15 分钟」(579 例)。盈利单同样受②约束。
//  ④ 过期同位等新K线: 挂单在K线中途过期后, 同一结构位绝不当场重挂(2025-26: 3/54, 2024: 0/48;
//     V5.2 当场重挂 126 次), 要等本策略周期下一根K线开盘; 若此时结构位已变(不同位)则当场挂出。
//  ⑤ 替换顺序: 原版先挂新单、后删旧单(旧单撤销时间恒 ≥ 新单挂出时间, 晚 0–3 秒)。
//  ⑥ 左臂历史截断: 测试起点历史不足时, 原版用已有K线判定左臂(2024.01.04 开局 A/B/C/E 立即挂在
//     2078.877 = 01-02 高点; V5.2 因左臂凑不满只挂出 D)。仅在 CopyRates 返回根数不足(历史起点)时生效。
//  尚未锁死(如实标注, 需要逐 tick 或 M1 数据才能定标, 详见《黄金城V5.3_逆向深挖报告.md》):
//  ⑦ 非平仓触发的挂单(过期后重挂/盘中替换/开局首挂)要等价格创出某个参考极值 R 才挂出: 卖单在价格
//     创新高时、买单在价格创新低时挂出(2024: 买 195 降/15 升, 卖 236 升/13 降), 且触发价恒为过期以来的
//     极值(违例 4/277)。R 不是订单价位、不是固定距离、不是日/周高低点 —— 报告样本不足以反解, 本版不实现。
//  ⑧ 盘中价格越过结构位后何时换位: 75 例原版沿用原位(价格回落再挂), 191 例立即换下一位, 判别条件同⑦待定。
//  V5.2 修订依据 —— 用与原版报告同源的 Exness XAUUSDm 逐笔数据(2025.01–2026.10, 1.56 亿 tick),
//  自建 C++ 仿真器逐 tick 复现 MT5「每笔即时价格(基于真实报价)」:先用它跑 V5 源码,与 V5 的
//  MT5 回测报告比对 —— 挂单 5064/5066、入场 1977/1977、出场 1977/1977 逐秒逐价一致(仿真器 = 测试器),
//  再拿它对原版报告做证伪, 只采纳逐笔可复现的结论:
//  ① 波动单位 U = 0.002 × Ask(V5 用 Bid)。原版 4211 张挂单中 4207 张(99.9%)的 价位/止损/止盈
//     三者同时逐位复现;买缓冲 = 0.1435U、卖缓冲 = 0.2580U(V5 的 0.143380/0.258183 是近似值)。
//  ② 结构位 = 非对称枢轴(左臂≠右臂), 由原版每次采纳的结构位反查 K 线得出(右臂取采纳时刻的
//     精确值, 左臂取全样本最小值, 二者界线清晰):
//        A: H2 左9/右7   B: D1 左19/右1   C: H4 左7/右3   D: H2 左5/右6   E: H2 左7/右3
//     原版下单时的结构位 = 「最近的未击穿枢轴」约 90%(其余为状态机延迟)。
//  ③ 追踪止损机制(V5 方向反了): 买单跟踪 Bid 新高、卖单跟踪 Ask 新低;追踪候选价只在出现
//     「新极值」那个 tick 用当时的 U 计算一次, 之后不随 U 漂移(V5 每 tick 重算会把止损越收越紧);
//     入场重锚 = 开仓价 ∓ (止损×U + 实时点差) 每 tick 评估。追踪倍数 A1.00 B3.00 C1.00 D3.00 E1.05;
//     追踪启动门槛: A 需浮盈 ≥ 0.6U, 其余 ≥ 0(进入浮盈即启动)。
//     逐仓验证: 原版 1771 笔出场中 1735 笔(98.0%)出场时间与价格逐 tick 复现(V5 模型仅 162 笔)。
//  ④ 测试器环境(非 EA 逻辑, 回测时请知悉): XAUUSDm_EX 交易时段在周一至周五 20:58–22:00(UTC)
//     关闭 —— 该时段有报价但测试器不成交、不触发止损/挂单、不过期, EA 的下单/改单/删单全部被拒。
//     这就是 FridayDelPend=21 从未删过单、挂单都在周日开盘才过期的原因。
//  ⑤ 仍未完全锁死(如实标注): 「价格越过结构位后, 该结构位何时作废、何时被原样复用」的精确条件。
//     原版约 17% 的补挂复用了已被价格越过的同一结构位, 且周末集体过期后的卖单补挂时刻有全局门控;
//     仿真中测试了 9 种候选规则, 均劣于当前事件状态机, 故本版保持事件状态机。
//  V5.1 修订依据 (原版 2025.01–2026.10 全样本 1771 笔 vs V5 1977 笔逐项对账, 仅用回测报告推导)
//  ① 周日开盘: 原版在周日 22:05/23:05 开盘第一个 tick 即布防(全期 540 张), V5 把周日整天封锁,
//     导致周一 01:00 集中补挂 552 张。原版只封「周一 00:00–00:59」(= Inp_MondayResume)。
//  ② 亏损冷却失效: V5 亏损平仓后 254 次 0 秒立即补挂(仅 29 次等足 900 秒); 原版 374 次精确 900 秒。
//     根因: 测试器里 OnTick 先于 OnTradeTransaction 执行, 冷却戳晚了一拍 → 改为 OnTick 内同步判定。
//  ③ 追踪倍数: 同 tick 同价成交的 A/C 两单, 原版 17/25 组在同一 tick 平仓(V5 仅 2/26) → A 与 C 同宽;
//     平仓注释里的止损价差 → A=1.00 C=1.00 E=1.05 D=3.00 (D−E 极值差 1.95U); B−C=2.001U → B=3.00。
//  ④ B 不是极值模式: 原版 B 挂单距现价中位 8U(买)/23U(卖), 成交 61 笔; V5 极值模式为 31U/182U,
//     卖侧全期 0 成交 → 改回「最近未击穿分形」, 与其余四套同一引擎。
//  ⑤ 分形臂: 以 V5 已知臂数的 H2 结构位序列为标尺比对原版结构位 → D 买臂 = 5 (臂5独有命中37次 vs
//     臂6独有4次); E 买与臂 5/6/7 均不吻合(392/636) → E 买臂 = 3 (与卖侧同臂)。
//  ⑥ OnTester: 原版回测报告 OnTester 结果 14415.35 = 盈利因子 × 采收率 × 夏普 × √交易数, 本版复刻。
//  ⑦ 接入四个模块(对交易逻辑零影响): UI面板独立模块 v2.7(+核心 v1.3) / 品种自适应 v1.1 /
//     指令挂单遥控 v1.1 —— 原 "MT5" 模块内部是 MQL4 API, 已移植为 MQL5 原生版(新文件, 原件不动)。
#property copyright "tradingvisionx (replica)"
#property link      "https://tradingvisionx.com/"
#property version   "5.30"
#property strict

#include <Trade\Trade.mqh>
#include "UI面板独立模块_MT5_v2.7.mqh"      // 内含 UI面板核心模块_MT5_v1.3.mqh
#include "品种自适应模块_MT5_v1.1.mqh"
#include "指令挂单遥控模块_MT5_v1.1.mqh"

#define GH_VERSION "V5.3"

//==================================================================//
//                          输入参数区                              //
//   参数名与原版 .set 逐字节对齐,可直接加载「原版.set」            //
//==================================================================//

input string sep_general        = "========== General ==========";                    // ---
input string sep_note           = "Not recommended to enable all strategies below $500"; // *** 提示 ***
input bool   RunPendingA        = true;      // [策略A] 启用  (H2摆动 · 止损1.5U · 止盈11.5U)
input bool   RunPendingB        = true;      // [策略B] 启用  (D1摆动 · 止损5U · 止盈10.5U)
input bool   RunPendingC        = true;      // [策略C] 启用  (H4摆动 · 止损1.5U · 止盈7.5U)
input bool   RunPendingD        = true;      // [策略D] 启用  (H2摆动 · 止损1.5U · 止盈12.5U · 宽追踪)
input bool   RunPendingE        = true;      // [策略E] 启用  (H2摆动 · 止损1.4U · 止盈11.5U)
input int    Inp_BaseMagic      = 1190;      // 魔术号基数 (每个EA实例唯一)
input string Inp_TradeComment   = "Gold House"; // 订单注释前缀
input double Inp_MaxSpreadPts   = 500.0;     // 最大允许点差 (点, 500 = 5.0 pip)
input bool   Inp_DeleteOnRemove = true;      // 卸载EA时删除本EA的挂单

input string sep_conservative   = "========== Conservative Mode ==========";          // ---
input bool   Inp_ConservativeMode = false;   // 保守模式 (资金安全优先于收益)

input string sep_lots           = "========== Lot Size ==========";                   // ---
enum ENUM_LOT_MODE
  {
   LOT_FIXED   = 0,   // 固定手数
   LOT_BALANCE = 1,   // 按结余递增 (每2000美元)
   LOT_MARGIN  = 2,   // 按预付款递增 (固定资本·启动时锁定)
   LOT_RISK    = 3,   // 按风险百分比 (依止损距离自动算)
   LOT_EQUITY  = 4    // 按净值递增 (每2000美元)
  };
input ENUM_LOT_MODE Inp_LotMode = LOT_FIXED; // 手数模式 (选定后在下方对应项填数值)
input double Inp_FixedLots      = 0.01;      // 每单固定手数
input double Inp_LotsPerStep    = 0.01;      // 每 2000 美元结余 的手数
input double Inp_MarginLotStep  = 0.01;      // 每 2000 美元预付款 的手数 (启动时锁定)
input double Inp_RiskPct        = 0.5;       // 每单风险百分比 (依止损距离自动计算)
input string sep_lots_misc      = "";        // ---
input double Inp_MaxLotSize     = 0.0;       // 每单最大手数 (0 = 用券商上限)
input bool   AutoRate           = true;      // 自动汇率换算
input double Inp_ExchangeRate   = 1.0;       // 手动汇率 (AutoRate=false 时生效)

input string sep_dd             = "========== Risk Management ==========";            // ---
input double Inp_MaxDrawdownPct = 0.0;       // 峰值净值最大回撤% (0=关闭; 原版默认0)
input double Inp_DailyDDPct     = 0.0;       // 单日最大回撤% (0=关闭; 原版默认0)
input bool   Inp_DDAccountWide  = true;      // 回撤口径: true=账户净值 / false=仅本EA盈亏
input double Inp_MarginReservePct = 5.0;     // 预留可用预付款缓冲% (0=关闭; 原版默认5)
input bool   Inp_MarginCheck    = true;      // 下单前预检预付款
input bool   Inp_CloseAll       = false;     // 回撤动作: true=平账户全部 / false=仅平本EA
input int    Inp_SLCooldownMin  = 15;        // 触发止损后冷却分钟 (0 = 关闭; V5.3 起同时为槽位挂单节流间隔)

input string sep_weekend        = "========== Weekend Protection ==========";         // ---
input bool   Inp_WeekendClose   = true;      // 启用周末自动清仓
input int    Inp_FridayNoEntry  = 19;        // 周五: 该小时后停止新挂单 (0=关闭; 会被删单/平仓小时自动钳制)
input int    Inp_FridayDelPend  = 21;        // 周五: 该小时后删除全部挂单 (0 = 关闭)
input int    Inp_FridayClosePos = 23;        // 周五: 该小时后平掉持仓 (0 = 关闭)
input int    Inp_MondayResume   = 1;         // 周一: 0点至该小时前暂停挂单 (0=不暂停; 周日开盘照常布防)

input string sep_news           = "========== News Filter ==========";                // ---
input bool   Inp_UseNewsFilter  = false;     // 启用新闻过滤 (仅高影响)
input int    Inp_NewsMinBefore  = 60;        // 新闻前封锁分钟
input int    Inp_NewsMinAfter   = 30;        // 新闻后封锁分钟
input bool   Inp_DeleteOnNews   = true;      // 新闻窗口内删除挂单

input string sep_ui             = "========== Display ==========";                    // ---
input bool   Inp_ShowPanel      = true;      // 显示图表信息面板
input bool   Inp_ShowBoundary   = true;      // 绘制上下边界线
input color  Inp_UpperLineClr   = clrGold;   // 上边界线颜色
input color  Inp_LowerLineClr   = clrAqua;   // 下边界线颜色

//------------------------------------------------------------------//
//  ↓↓↓ 以下为复刻版新增的「引擎标定参数」。原版为硬编码常量,        //
//      此处开放以便你按自己的回测结果微调至完全吻合。               //
//      默认值 = 逆向反解出的实测值,直接加载原版.set 不受影响。     //
//------------------------------------------------------------------//
input string sep_engine         = "========== 引擎标定 (复刻版新增) ==========";      // ---
input double Inp_UnitPct        = 0.002;     // 波动单位 U = 该比例 × 当前Ask价 (V5.2 实测: 基准为 Ask)
input double Inp_BuyOffsetU     = 0.1435;    // 买挂单内缩缓冲 ×U (V5.2 逐笔实测 0.1435)
input double Inp_SellOffsetU    = 0.258;     // 卖挂单内缩缓冲 ×U (V5.2 逐笔实测 0.258)

input string sep_engA           = "---------- 策略A ----------";                      // ---
input ENUM_TIMEFRAMES Inp_A_TF  = PERIOD_H2; // A: 结构时间框
input int    Inp_A_Frac         = 7;         // A: 卖侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_A_FracB        = 7;         // A: 买侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_A_LeftS        = 9;         // A: 卖侧枢轴左臂根数 (V5.2 新增, H2 左9/右7)
input int    Inp_A_LeftB        = 9;         // A: 买侧枢轴左臂根数 (V5.2 新增)
input double Inp_A_SL           = 1.5;       // A: 止损 ×U
input double Inp_A_TP           = 11.5;      // A: 止盈 ×U
input double Inp_A_Trail        = 1.00;      // A: 追踪距离 ×U (V5.1 全样本重标定=1.00, 与C同tick平仓)
input double Inp_A_TrailStart   = 0.6;       // A: 追踪启动门槛 ×U (浮盈达到才开始追踪; V5.2 实测 A=0.6)
input int    Inp_A_ExpireH      = 60;        // A: 挂单有效期(小时)

input string sep_engB           = "---------- 策略B ----------";                      // ---
input ENUM_TIMEFRAMES Inp_B_TF  = PERIOD_D1; // B: 结构时间框
input int    Inp_B_Frac         = 1;         // B: 卖侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_B_FracB        = 1;         // B: 买侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_B_LeftS        = 19;         // B: 卖侧枢轴左臂根数 (V5.2 新增, D1 左19/右1)
input int    Inp_B_LeftB        = 19;         // B: 买侧枢轴左臂根数 (V5.2 新增)
input bool   Inp_B_Extreme      = false;     // B: 极值模式 (V5.1 关闭: 原版B挂单距价中位8U/23U, 属最近位)
input int    Inp_B_StructBars   = 120;       // B: 专属回溯根数 (仅极值模式开启时生效)
input double Inp_B_SL           = 5.0;       // B: 止损 ×U
input double Inp_B_TP           = 10.5;      // B: 止盈 ×U
input double Inp_B_Trail        = 3.00;      // B: 追踪距离 ×U (V5.1: B−C 止损差 2.001U → 3.00)
input double Inp_B_TrailStart   = 0.0;       // B: 追踪启动门槛 ×U (浮盈达到才开始追踪; V5.2 实测 0=进入浮盈即启动)
input int    Inp_B_ExpireH      = 310;       // B: 挂单有效期(小时) (V5.3 实测 310h; 周日开盘挂单因周末顺延才显示 336h)

input string sep_engC           = "---------- 策略C ----------";                      // ---
input ENUM_TIMEFRAMES Inp_C_TF  = PERIOD_H4; // C: 结构时间框
input int    Inp_C_Frac         = 3;         // C: 卖侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_C_FracB        = 3;         // C: 买侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_C_LeftS        = 7;         // C: 卖侧枢轴左臂根数 (V5.2 新增, H4 左7/右3)
input int    Inp_C_LeftB        = 7;         // C: 买侧枢轴左臂根数 (V5.2 新增)
input double Inp_C_SL           = 1.5;       // C: 止损 ×U
input double Inp_C_TP           = 7.5;       // C: 止盈 ×U
input double Inp_C_Trail        = 1.00;      // C: 追踪距离 ×U (原版实测1.00)
input double Inp_C_TrailStart   = 0.0;       // C: 追踪启动门槛 ×U (浮盈达到才开始追踪; V5.2 实测 0=进入浮盈即启动)
input int    Inp_C_ExpireH      = 60;        // C: 挂单有效期(小时)

input string sep_engD           = "---------- 策略D ----------";                      // ---
input ENUM_TIMEFRAMES Inp_D_TF  = PERIOD_H2; // D: 结构时间框
input int    Inp_D_Frac         = 6;         // D: 卖侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_D_FracB        = 6;         // D: 买侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_D_LeftS        = 5;         // D: 卖侧枢轴左臂根数 (V5.2 新增, H2 左5/右6)
input int    Inp_D_LeftB        = 5;         // D: 买侧枢轴左臂根数 (V5.2 新增)
input double Inp_D_SL           = 1.5;       // D: 止损 ×U
input double Inp_D_TP           = 12.5;      // D: 止盈 ×U
input double Inp_D_Trail        = 3.00;      // D: 追踪距离 ×U (原版实测3.00, D−E 极值差1.95U)
input double Inp_D_TrailStart   = 0.0;       // D: 追踪启动门槛 ×U (浮盈达到才开始追踪; V5.2 实测 0=进入浮盈即启动)
input int    Inp_D_ExpireH      = 60;        // D: 挂单有效期(小时)

input string sep_engE           = "---------- 策略E ----------";                      // ---
input ENUM_TIMEFRAMES Inp_E_TF  = PERIOD_H2; // E: 结构时间框
input int    Inp_E_Frac         = 3;         // E: 卖侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_E_FracB        = 3;         // E: 买侧枢轴右臂根数 (V5.2 逐笔实测)
input int    Inp_E_LeftS        = 7;         // E: 卖侧枢轴左臂根数 (V5.2 新增, H2 左7/右3)
input int    Inp_E_LeftB        = 7;         // E: 买侧枢轴左臂根数 (V5.2 新增)
input double Inp_E_SL           = 1.4;       // E: 止损 ×U
input double Inp_E_TP           = 11.5;      // E: 止盈 ×U
input double Inp_E_Trail        = 1.05;      // E: 追踪距离 ×U (原版实测1.05)
input double Inp_E_TrailStart   = 0.0;       // E: 追踪启动门槛 ×U (浮盈达到才开始追踪; V5.2 实测 0=进入浮盈即启动)
input int    Inp_E_ExpireH      = 60;        // E: 挂单有效期(小时)

input string sep_engMisc        = "---------- 通用引擎 ----------";                   // ---
input int    Inp_StructBars     = 600;       // 结构扫描回溯根数
input bool   Inp_UnbrokenOnly   = true;      // 仅采用「未被击穿」的摆动位

//------------------------------------------------------------------//
//  ↓↓↓ V5.3 新增「原版规则」开关 —— 默认 = 原版行为(三份原版报告逐单确认)  //
//      全部设为 false 即退回 V5.2 行为, 便于逐项 A/B 回测追溯             //
//------------------------------------------------------------------//
input string sep_v53            = "========== V5.3 原版规则 (逐单对账确认) ==========";  // ---
input bool   Inp_SlotThrottle   = true;      // [V5.3] 槽位挂单节流: 同策略同方向相邻两次挂单(含替换)间隔 ≥ 冷却分钟
input bool   Inp_LossAnchor     = true;      // [V5.3] 亏损冷却锚定: 亏损单挂单后不足冷却期即平仓时, 不再追加平仓冷却
input bool   Inp_ExpireWaitBar  = true;      // [V5.3] 过期同位等新K线: 挂单盘中过期后, 同一结构位等本策略周期新K线才重挂
input bool   Inp_PlaceThenDel   = true;      // [V5.3] 替换顺序: 先挂新单再删旧单 (false = V5.2 先删后挂)
input bool   Inp_LeftArmTrunc   = true;      // [V5.3] 左臂历史截断: 历史起点K线不足左臂根数时, 按已有K线判定枢轴

//------------------------------------------------------------------//
//  ↓↓↓ V5.1 新增模块参数 —— 对交易逻辑零影响(遥控在回测中永不运行)   //
//------------------------------------------------------------------//
input string sep_ui2            = "========== 界面与品种 (V5.1 新增) ==========";     // ---
input int    Inp_UIStyle        = 1;         // 面板样式: 0=原版复刻面板 / 1=全视界双栏面板
input int    Inp_SymbolAdaptMode= 0;         // 品种自适应: 0=自适应(黄金1pip=0.01美元) / 1=旧规则(5/3位)

input string sep_rc             = "========== 指令挂单遥控 (V5.1 新增) ==========";   // ---
input bool   Inp_RC_Enable      = false;     // 启用手机遥控 (改哨兵单止盈=发指令; 回测中永不运行)
input long   Inp_RC_Magic       = 1199;      // 遥控哨兵单魔术号 (不得与策略号 基数+1~+5 及其他EA冲突)
input long   Inp_RC_ManualMagic = 1198;      // 人工单魔术号 (遥控开仓/面板按钮开仓; 不进入策略逻辑)
input double Inp_RC_Price       = 3.0;       // 哨兵单挂单价位 (远低于现价, 永不成交)
input double Inp_RC_Lots        = 0.01;      // 哨兵单手数
input double Inp_RC_Standby     = 666;       // 待机码 (指令执行后自动写回作回执)
input double Inp_RC_ManualLots  = 0.01;      // 人工开多/开空手数 (面板手数框填 >0 时以手数框为准)
input double Inp_RC_CodeOpenBuy = 111;       // 指令码: 强制开多 (按A策略几何: 止损1.5U / 止盈11.5U)
input double Inp_RC_CodeOpenSell= 222;       // 指令码: 强制开空 (同上)
input double Inp_RC_CodeCloseAll= 555;       // 指令码: 平掉本EA全部持仓
input double Inp_RC_CodeBE      = 888;       // 指令码: 保本 (浮盈单止损移到开仓价 / 浮亏单止盈移到开仓价)
input double Inp_RC_CodePause   = 777;       // 指令码: 停开新挂单 (已有挂单与持仓照常管理)
input double Inp_RC_CodeResume  = 999;       // 指令码: 恢复全部 (解除停开/保本)

//==================================================================//
//                          全局对象与状态                          //
//==================================================================//
#define GH_PFX "GH_"                 // 图形对象前缀
#define GH_NSTRAT 5

CTrade  trade;

//--- 单套策略的配置与运行态
struct SStrat
  {
   bool              on;
   string            tag;            // "A".."E"
   ENUM_TIMEFRAMES   tf;
   int               frac;           // 卖侧(下摆)分形臂
   int               fracB;          // 买侧(上摆)枢轴右臂
   int               leftS, leftB;   // V5.2: 卖侧/买侧枢轴左臂(原版为非对称枢轴)
   double            trStart;        // V5.2: 追踪启动门槛 ×U
   bool              ext;            // 极值模式(B专属): 状态只向更远极值推进
   double            slU, tpU, trU;
   int               expH;
   long              magic;
   datetime          lastBar;        // 该策略时间框的上一根已处理K线
   datetime          lastCalc;       // 上次结构位重算时刻(空结构位时的节流锚)
   double            ceilv, floorv;  // 结构位状态 = 最近一次「确认」的分形高/低(事件驱动)
   double            armB, armS;     // 当前活跃挂单背后的结构位(替换判定用,消灭U漂移churn)
  };
SStrat  S[GH_NSTRAT];

//--- 市场常量
double  g_point, g_tick, g_pip, g_minLot, g_maxLot, g_lotStep;
int     g_digits, g_stopLvl;
double  g_startMargin  = 0.0;        // 固定资本模式:启动时锁定的预付款
double  g_peakEquity   = 0.0;
double  g_dayStartEq   = 0.0;
datetime g_dayStamp    = 0;
bool    g_halted       = false;      // 回撤熔断
bool    g_haltDaily    = false;      // 熔断来源是「单日回撤」→ 换日自动复位
double  g_exRate       = 1.0;

//--- 分槽冷却:亏损性止损后,该策略该方向冷却 Inp_SLCooldownMin 分钟
//    (原版实测:亏损SL→补挂时滞中位数精确=900秒;盈利性平仓→0秒立即补挂)
datetime g_coolTo[GH_NSTRAT][2];     // [策略][0=买/1=卖]

//--- V5.1 槽位同步表: 上一 tick 各「策略×方向」槽内持仓的 POSITION_IDENTIFIER (0=空槽)
//    OnTick 开头比对 → 持仓消失即判定平仓 → 查该持仓历史成交净盈亏 → 亏损则当场写冷却戳。
//    取代 V5 的 OnTradeTransaction 冷却(测试器中它晚于 OnTick 触发, 亏损单被 0 秒补挂 254 次)。
ulong   g_slotPid[GH_NSTRAT][2];

//--- V5.3 槽位挂单节流 / 过期同位封锁 (原版规则②③④)
datetime g_slotTimer[GH_NSTRAT][2];  // 该槽下一次允许挂单的最早时刻 = 上次挂单时刻 + 冷却分钟
ulong    g_slotOrd[GH_NSTRAT][2];    // 上一 tick 该槽的挂单 ticket (用于识别「过期消失」)
double   g_expLvl[GH_NSTRAT][2];     // 最近一次「过期」挂单背后的结构位 (0 = 无封锁)
datetime g_expBar[GH_NSTRAT][2];     // 过期发生时本策略周期所处的K线开盘时间 (新K线开盘即解封)
bool     g_defRep[GH_NSTRAT][2];     // 新K线替换被节流挡住 → 节流到期后补做一次替换判定

//--- V5.1 面板/遥控运行态(纯显示与人工操作, 不参与策略判定)
bool     g_uiLive     = false;       // 全视界面板是否在渲染(非可视回测=false, 零开销)
bool     g_uiPaused   = false;       // 面板「暂停」: 只停新挂单, 持仓照常追踪
double   g_uiMaxDD    = 0.0;         // 运行以来本EA浮亏峰值(正数)
datetime g_uiMaxDDT   = 0;
string   g_uiLastAct  = "";
datetime g_uiStatT    = 0;           // 分策略已平统计的刷新时刻
int      g_stN[GH_NSTRAT], g_stW[GH_NSTRAT];
double   g_stP[GH_NSTRAT];

//--- 追踪极值表:每个持仓的「成交侧价格」运行极值(买=Ask极大, 卖=Bid极小)
struct STrack { ulong tk; double m; double trs; };   // V5.2: trs = 最近一次「新极值」时算出的追踪候选价
STrack  g_trk[64];
int     g_ntrk = 0;
int     g_lotDigits    = 2;          // 手数小数位(依券商 VOLUME_STEP 推导)
int     g_fridayNoEntry= 0;          // 钳制后的周五停单小时(≤删单小时)
ENUM_ORDER_TYPE_TIME g_ttype = ORDER_TIME_SPECIFIED; // 券商支持的挂单到期模式
bool    g_newsBlock    = false;      // 新闻窗口缓存(每秒刷新一次)

//--- 面板显示缓存
double  g_uiCeil = 0, g_uiFloor = 0;
int     g_uiCeilOrd = 0, g_uiFloorOrd = 0;
double  g_uiCeilLot = 0, g_uiFloorLot = 0;

//==================================================================//
//                            初始化                                //
//==================================================================//
int OnInit()
  {
   g_digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(g_point <= 0)
     {
      Print("FATAL: SYMBOL_POINT = 0,品种规格未同步,EA 拒绝启动");
      return(INIT_FAILED);
     }
   g_tick    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tick <= 0) g_tick = g_point;
   g_pip     = (g_digits == 3 || g_digits == 5) ? g_point * 10.0 : g_point;
   if(g_pip <= 0) g_pip = g_point;
   g_stopLvl = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   trade.SetExpertMagicNumber(Inp_BaseMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);
   trade.LogLevel(LOG_LEVEL_ALL);

   SetupStrategy(0, "A", RunPendingA, Inp_A_TF, Inp_A_Frac, Inp_A_SL, Inp_A_TP, Inp_A_Trail, Inp_A_ExpireH);
   SetupStrategy(1, "B", RunPendingB, Inp_B_TF, Inp_B_Frac, Inp_B_SL, Inp_B_TP, Inp_B_Trail, Inp_B_ExpireH);
   SetupStrategy(2, "C", RunPendingC, Inp_C_TF, Inp_C_Frac, Inp_C_SL, Inp_C_TP, Inp_C_Trail, Inp_C_ExpireH);
   SetupStrategy(3, "D", RunPendingD, Inp_D_TF, Inp_D_Frac, Inp_D_SL, Inp_D_TP, Inp_D_Trail, Inp_D_ExpireH);
   SetupStrategy(4, "E", RunPendingE, Inp_E_TF, Inp_E_Frac, Inp_E_SL, Inp_E_TP, Inp_E_Trail, Inp_E_ExpireH);
   S[1].ext = Inp_B_Extreme;      // B 专属:极值结构位模式
   // 买侧分形臂独立标定(E 的买臂6>卖臂3,原版买单在4221钉两周的指纹)
   S[0].fracB = MathMax(1, Inp_A_FracB);
   S[1].fracB = MathMax(1, Inp_B_FracB);
   S[2].fracB = MathMax(1, Inp_C_FracB);
   S[3].fracB = MathMax(1, Inp_D_FracB);
   S[4].fracB = MathMax(1, Inp_E_FracB);
   // V5.2: 非对称枢轴左臂 + 追踪启动门槛
   S[0].leftS = MathMax(1, Inp_A_LeftS); S[0].leftB = MathMax(1, Inp_A_LeftB); S[0].trStart = Inp_A_TrailStart;
   S[1].leftS = MathMax(1, Inp_B_LeftS); S[1].leftB = MathMax(1, Inp_B_LeftB); S[1].trStart = Inp_B_TrailStart;
   S[2].leftS = MathMax(1, Inp_C_LeftS); S[2].leftB = MathMax(1, Inp_C_LeftB); S[2].trStart = Inp_C_TrailStart;
   S[3].leftS = MathMax(1, Inp_D_LeftS); S[3].leftB = MathMax(1, Inp_D_LeftB); S[3].trStart = Inp_D_TrailStart;
   S[4].leftS = MathMax(1, Inp_E_LeftS); S[4].leftB = MathMax(1, Inp_E_LeftB); S[4].trStart = Inp_E_TrailStart;

   // 手数小数位:依券商 VOLUME_STEP 推导,兼容 0.001 手长的微型/ECN 账户
   g_lotDigits = (g_lotStep > 0) ? (int)MathMax(0, MathCeil(-MathLog10(g_lotStep))) : 2;

   // 挂单到期模式探测:券商不支持「指定时间」时退回 GTC,由 EA 自行按有效期删单
   long expMode = SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
   g_ttype = ((expMode & SYMBOL_EXPIRATION_SPECIFIED) != 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;
   if(g_ttype == ORDER_TIME_GTC)
      Print("NOTE: 本品种不支持指定到期时间,改用 GTC + EA 端到期回收");

   // 周五阈值钳制:防止「入场闸仍开、删单闸已开」的重叠区形成删-挂死循环
   g_fridayNoEntry = Inp_FridayNoEntry;
   if(Inp_FridayDelPend > 0)
      g_fridayNoEntry = (g_fridayNoEntry <= 0) ? Inp_FridayDelPend
                                               : (int)MathMin(g_fridayNoEntry, Inp_FridayDelPend);
   if(Inp_FridayClosePos > 0)    // 平仓闸也纳入钳制:否则会「挂上→成交→秒平→再挂」反复放血
      g_fridayNoEntry = (g_fridayNoEntry <= 0) ? Inp_FridayClosePos
                                               : (int)MathMin(g_fridayNoEntry, Inp_FridayClosePos);
   if(g_fridayNoEntry != Inp_FridayNoEntry)
      PrintFormat("[%s] 周五停单小时已自动钳制: %d → %d", Inp_TradeComment, Inp_FridayNoEntry, g_fridayNoEntry);

   for(int i = 0; i < GH_NSTRAT; i++) { g_coolTo[i][0] = 0; g_coolTo[i][1] = 0; }
   g_ntrk = 0;

   g_startMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   g_peakEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEq  = g_peakEquity;
   g_dayStamp    = DayStamp(TimeCurrent());
   g_exRate      = CalcExchangeRate();
   for(int i = 0; i < GH_NSTRAT; i++) { g_slotPid[i][0] = 0; g_slotPid[i][1] = 0; }
   for(int i = 0; i < GH_NSTRAT; i++)
      for(int d = 0; d < 2; d++)
        { g_slotTimer[i][d] = 0; g_slotOrd[i][d] = 0; g_expLvl[i][d] = 0.0; g_expBar[i][d] = 0; g_defRep[i][d] = false; }

   //--- V5.1 模块: 品种自适应(仅用于显示 pip 口径与日志)
   SA_Init(Inp_SymbolAdaptMode);

   //--- V5.1 魔术号冲突守卫: 人工单/哨兵单绝不能落在策略号上, 否则会被当成策略持仓占槽
   if(IsMine(Inp_RC_ManualMagic) || IsMine(Inp_RC_Magic) || Inp_RC_Magic == Inp_RC_ManualMagic)
     {
      PrintFormat("FATAL: 魔术号冲突 —— 人工单 %I64d / 哨兵单 %I64d 不得等于策略号 %d~%d 或基数 %d, 两者也不得相同",
                  Inp_RC_ManualMagic, Inp_RC_Magic, Inp_BaseMagic + 1, Inp_BaseMagic + GH_NSTRAT, Inp_BaseMagic);
      return(INIT_PARAMETERS_INCORRECT);
     }

   //--- V5.1 模块: 指令挂单遥控(回测中 RC_Active()=false → 不挂单、不轮询)
   RC_Setup(Inp_RC_Enable, Inp_RC_Magic, Inp_RC_Price, Inp_RC_Lots, Inp_RC_Standby,
            true, true, true, 30, "[" + Inp_TradeComment + " 遥控] ",
            "GH_RC_" + IntegerToString(Inp_RC_Magic) + "_" + _Symbol + "_", "GH_CMD", false);
   RC_SetCode(1, Inp_RC_CodeOpenBuy,  RC_CMD_OPEN_BUY);
   RC_SetCode(2, Inp_RC_CodeOpenSell, RC_CMD_OPEN_SELL);
   RC_SetCode(3, Inp_RC_CodeCloseAll, RC_CMD_CLOSE_ALL);
   RC_SetCode(4, Inp_RC_CodeBE,       RC_CMD_TP_TO_BE);
   RC_SetCode(5, Inp_RC_CodePause,    RC_CMD_PAUSE_NEW);
   RC_SetCode(6, Inp_RC_CodeResume,   RC_CMD_RESUME);
   RC_LoadState();

   PrintFormat("===== %s v2.0 Started =====", Inp_TradeComment);
   PrintFormat("[%s] ExRate: %s Auto=%d", Inp_TradeComment,
               AccountInfoString(ACCOUNT_CURRENCY), (int)AutoRate);
   DailyCheckLog();
   PrintFormat("[%s] 复刻版 %s | 品种 %s", Inp_TradeComment, GH_VERSION, SA_Describe());
   if(Inp_RC_Enable)
      PrintFormat("[%s] 遥控 %s | 码位 %s", Inp_TradeComment, RC_StatusText(), RC_CodeMap());

   if(Inp_ShowPanel)
     {
      if(Inp_UIStyle == 1) GH_UiInit();
      else                 BuildPanel();
     }
   ChartRedraw();
   return(INIT_SUCCEEDED);
  }

void SetupStrategy(int i, string tag, bool on, ENUM_TIMEFRAMES tf, int frac,
                   double sl, double tp, double tr, int expH)
  {
   S[i].on     = on;
   S[i].tag    = tag;
   S[i].tf     = tf;
   S[i].frac   = MathMax(1, frac);
   S[i].fracB  = MathMax(1, frac);   // 默认对称;OnInit 尾部按 Inp_X_FracB 覆盖
   S[i].leftS  = S[i].frac;          // 默认对称;OnInit 尾部按 Inp_X_LeftS/LeftB 覆盖
   S[i].leftB  = S[i].fracB;
   S[i].trStart= 0.0;
   S[i].ext    = false;
   S[i].slU    = sl;
   S[i].tpU    = tp;
   S[i].trU    = tr;
   S[i].expH   = expH;
   S[i].magic   = Inp_BaseMagic + i + 1;
   S[i].lastBar = 0;
   S[i].lastCalc= 0;
   S[i].ceilv   = 0;
   S[i].floorv  = 0;
   S[i].armB    = 0;
   S[i].armS    = 0;
  }

//==================================================================//
//                            反初始化                              //
//==================================================================//
void OnDeinit(const int reason)
  {
   // 只有「手工移除EA / 程序自行退出」才清挂单。
   // 终端关闭(9)、重新编译(2)、换模板(7)、关图(4)、换账户(6) 一律保留服务器端布防,
   // 否则 VPS 夜间重启或随手改一次代码就会把十个方向的挂单全部抹掉。
   if(Inp_DeleteOnRemove && (reason == REASON_REMOVE || reason == REASON_PROGRAM))
     {
      int want = 0, done = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0) continue;
         if(!IsMine((long)OrderGetInteger(ORDER_MAGIC))) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         want++;
         if(trade.OrderDelete(tk)) { done++; PrintFormat("  Deleted order #%I64u", tk); }
        }
      if(want > 0) PrintFormat("  Cleanup complete: deleted %d/%d order(s)", done, want);
     }
   ObjectsDeleteAll(0, GH_PFX);
   if(UiHasPanel() || g_uiLive) UiDeinit();
   PrintFormat("===== %s Stopped | Code %d =====", Inp_TradeComment, reason);
   ChartRedraw();
  }

//==================================================================//
//                              主循环                              //
//==================================================================//
void OnTick()
  {
   SyncSlots();                   // V5.1: 槽位同步 → 平仓即判冷却(必须在任何布防之前)
   SyncOrders();                  // V5.3: 挂单同步 → 识别「过期消失」的挂单, 登记过期同位封锁(规则④)
   RefreshRisk();                 // 风控:回撤 / 熔断 / 冷却
   RefreshNews();                 // 新闻窗口(每秒一次,把重活挪出tick路径)
   ManageWeekend();               // 周末保护
   ExpireByAge();                 // GTC 模式下的 EA 端到期回收
   ManageTrailing();              // 追踪止损(逐tick)
   GH_RemoteControl();            // V5.1: 手机遥控(回测中立即返回)

   bool allow = TradingAllowed();
   for(int i = 0; i < GH_NSTRAT; i++)
     {
      if(!S[i].on) continue;
      datetime bt = (datetime)SeriesInfoInteger(_Symbol, S[i].tf, SERIES_LASTBAR_DATE);
      bool newBar = (bt != S[i].lastBar);

      // 结构位每根策略K线刷新一次(重活只在换K线时做);
      // 找不到结构位时最多每 60 秒重试,绝不允许退化成逐 tick 全量扫描
      if(newBar) S[i].lastBar = bt;
      double _ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double _bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // ① 事件驱动:每根策略K线闭合时,检查「刚获得完整右臂」的分形中心。
      //    若确认,无条件采纳为新结构位状态(哪怕比现状态更远——原版实证如此)。
      if(newBar) OnFractalEvent(i, _bid, _ask);

      // ② 自举/失效重扫:状态为空,或价格已穿越到状态位另一侧(该方向无法布防)
      //    时,退回「最近的未击穿分形」全扫描。60 秒节流,绝不逐 tick 扫。
      //    双侧独立判定:floor 失效不应顺带重写健康的 ceil(反之亦然)
      bool weakUp = (S[i].ceilv  <= _ask);
      bool weakDn = (S[i].floorv <= 0) || (S[i].floorv >= _bid);
      // B(极值模式) 卖侧无自举:只等日线分形确认事件。
      // 原版实证:B 卖单直到 06-12 事件确认才首挂;v4 的自举在 06-08 多挂出一单,
      // 恰是全场最差亏损(-22.19)的来源。B 的卖状态一旦确立只向更低棘轮,永不重扫。
      if(S[i].ext) weakDn = false;
      if((weakUp || weakDn) && TimeCurrent() - S[i].lastCalc >= 60)
        { UpdateLevels(i, weakUp, weakDn); S[i].lastCalc = TimeCurrent(); }

      if(allow) ArmPendings(i, newBar);
     }

   DailyCheckLog();

   // 面板/边界线节流:每秒最多重绘一次,避免逐tick刷屏拖慢测试器
   static datetime uiStamp = 0;
   if(TimeCurrent() != uiStamp)
     {
      uiStamp = TimeCurrent();
      if(Inp_ShowPanel)
        {
         if(Inp_UIStyle == 1) { if(g_uiLive) { GH_UiButtons(); GH_UiRender(); } }
         else                 UpdatePanel();
        }
      if(Inp_ShowBoundary) DrawBoundary(); else DeleteBoundary();
     }
  }

//==================================================================//
//  结构位状态机 (v3,对账原版 141 次替换事件后的精确模型):          //
//                                                                  //
//  · 常态 = 事件驱动:策略K线闭合 → 若「arm+1 根前的K线」恰好      //
//    集齐右臂(左右各 arm 根都更低/更高) → 该分形刚刚「确认」→     //
//    无条件采纳为新状态(原版实证:状态可以变得更远,如 E 在        //
//    4351→4362;挂单只在状态「更近」时才替换)。                    //
//  · 自举 = 启动时或价格穿越状态位后,退回「最近未击穿分形」全扫。 //
//  · 替换判定在「结构位」层面比较,而非挂单价——挂单价含 U(0.2%×现 //
//    价)项会随价格漂移,v2 版按挂单价比较导致 1009 次自我churn。   //
//==================================================================//

//--- 事件:刚闭合的策略K线使某个分形中心「集齐右臂」→ 采纳
//    买侧/卖侧臂数独立:armB(上摆) 与 arm(下摆) 的候选中心不同
void OnFractalEvent(int i, double bid, double ask)
  {
   int armS = S[i].frac,  lefS = S[i].leftS;     // V5.2: 右臂(确认用) / 左臂(形态用) 非对称
   int armB = S[i].fracB, lefB = S[i].leftB;
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int need = MathMax(armS + lefS, armB + lefB) + 3;
   int got  = CopyRates(_Symbol, S[i].tf, 0, need, r);
   // V5.3 规则⑥: 历史起点K线不足左臂时, 按已有K线判定(原版开局即用短历史结构位); 关闭则沿用 V5.2 硬要求
   if(got < need && (!Inp_LeftArmTrunc || got < MathMax(armS, armB) + 2)) return;

   //---- 枢轴高确认? (右臂 armB 根已收盘K线, 左臂 lefB 根更早K线, 中心 = armB+1)
   int kB = armB + 1;
   bool isHigh = (kB < got);
   for(int j = 1; j <= armB && isHigh; j++) if(r[kB].high <= r[kB - j].high) isHigh = false;
   for(int j = 1; j <= lefB && isHigh && kB + j < got; j++) if(r[kB].high <= r[kB + j].high) isHigh = false;
   if(isHigh && r[kB].high > ask)        // 价格侧有效才采纳
     {
      // 普通策略:无条件采纳(状态可以变得更远,原版实证);
      // B 极值模式:只向「更高的上摆」推进,轻易不换位
      if(!S[i].ext || S[i].ceilv == 0 || r[kB].high > S[i].ceilv)
         S[i].ceilv = r[kB].high;
     }

   //---- 分形低确认? (卖侧臂 armS, 候选中心 = armS+1)
   int kS = armS + 1;
   bool isLow = (kS < got);
   for(int j = 1; j <= armS && isLow; j++) if(r[kS].low >= r[kS - j].low) isLow = false;
   for(int j = 1; j <= lefS && isLow && kS + j < got; j++) if(r[kS].low >= r[kS + j].low) isLow = false;
   if(isLow && r[kS].low < bid)
     {
      if(!S[i].ext || S[i].floorv == 0 || r[kS].low < S[i].floorv)
         S[i].floorv = r[kS].low;
     }
  }

//==================================================================//
//        自举扫描:分形摆动高/低 → 未击穿过滤 → 最近上下位        //
//==================================================================//
void UpdateLevels(int i, bool wUp = true, bool wDn = true)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   // B 专属回溯窗:600 根 D1 会抓到 2.4 年外的历史极值(原版实测只钉在≈4888 的近月峰,
   // 说明其扫描窗更短)。其余策略沿用全局 Inp_StructBars。
   int wantBars = (S[i].ext && Inp_B_StructBars > 0) ? Inp_B_StructBars : Inp_StructBars;
   int need = MathMin(wantBars, 5000);
   int n = CopyRates(_Symbol, S[i].tf, 0, need, r);
   int armS = S[i].frac,  lefS = S[i].leftS;
   int armB = S[i].fracB, lefB = S[i].leftB;
   // V5.3 规则⑥: CopyRates 返回根数 < 请求根数 = 已到图表历史起点 → 左臂按已有K线判定(原版开局行为)。
   //   历史充足(n == need)时左臂仍须完整, 与 V5.2 逐位一致。
   bool trunc = (Inp_LeftArmTrunc && n > 0 && n < need);
   if(n <= 0) return;
   if(!trunc && n < MathMax(armS + lefS, armB + lefB) + 5) return;
   if( trunc && n < MathMax(armS, armB) + 2) return;
   int endB = trunc ? n : n - lefB;
   int endS = trunc ? n : n - lefS;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double bestUp = 0.0, bestDn = 0.0;

   // 前缀极值:pMax[k] = max(r[0..k-1].high) —— 即「该分形形成之后的最高价」
   // 一次线性扫描替代 O(n²) 击穿判定,回测中必须如此,否则逐tick会拖死测试器
   double pMax[], pMin[];
   ArrayResize(pMax, n); ArrayResize(pMin, n);
   pMax[0] = -DBL_MAX; pMin[0] = DBL_MAX;
   for(int k = 1; k < n; k++)
     {
      pMax[k] = MathMax(pMax[k - 1], r[k - 1].high);
      pMin[k] = MathMin(pMin[k - 1], r[k - 1].low);
     }

   // r[0] 为当前未完成K线。买侧臂 armB / 卖侧臂 armS 各自独立扫描。
   for(int k = armB + 1; k < endB; k++)
     {
      //---------------- 枢轴高 (右臂 armB / 左臂 lefB) ----------------
      bool isHigh = true;
      for(int j = 1; j <= armB && isHigh; j++) if(r[k].high <= r[k - j].high) isHigh = false;
      for(int j = 1; j <= lefB && isHigh && k + j < n; j++) if(r[k].high <= r[k + j].high) isHigh = false;
      if(isHigh && r[k].high > ask)
        {
         bool broken = (Inp_UnbrokenOnly && pMax[k] > r[k].high);
         if(!broken)
           {
            // 普通=取最近(最低的上摆);B极值=取最高的上摆
            bool take = (bestUp == 0.0) || (S[i].ext ? r[k].high > bestUp : r[k].high < bestUp);
            if(take) bestUp = r[k].high;
           }
        }
     }
   for(int k = armS + 1; k < endS; k++)
     {
      //---------------- 枢轴低 (右臂 armS / 左臂 lefS) ----------------
      bool isLow = true;
      for(int j = 1; j <= armS && isLow; j++) if(r[k].low >= r[k - j].low) isLow = false;
      for(int j = 1; j <= lefS && isLow && k + j < n; j++) if(r[k].low >= r[k + j].low) isLow = false;
      if(isLow && r[k].low < bid)
        {
         bool broken = (Inp_UnbrokenOnly && pMin[k] < r[k].low);
         if(!broken)
           {
            // 普通=取最近(最高的下摆);B极值=取最低的下摆
            bool take = (bestDn == 0.0) || (S[i].ext ? r[k].low < bestDn : r[k].low > bestDn);
            if(take) bestDn = r[k].low;
           }
        }
     }

   if(wUp) S[i].ceilv  = bestUp;   // 只重写「失效的那一侧」;找不到时归零 → 该方向暂不布防
   if(wDn) S[i].floorv = bestDn;
  }

//==================================================================//
//               挂单引擎:布防 / 择近替换 / 到期重挂              //
//  ★ 铁律1(占槽): 同策略同方向「挂单+持仓」互斥,持仓在场绝不补挂  //
//     —— 原版 98/98 零违例;复刻版上一版少了这条,堆出 108 并发仓  //
//  ★ 铁律2(冷却): 亏损性止损后该槽冷却 SLCooldownMin 分钟;        //
//     盈利性平仓(追踪锁盈)立即补挂 —— 时滞中位数实测 900s / 0s     //
//==================================================================//
void ArmPendings(int i, bool newBar)
  {
   if(g_uiPaused || RC_BlockNew()) return;   // V5.1: 面板暂停 / 遥控停开 (回测默认恒为 false)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double U   = Unit();
   if(U <= 0) return;

   //================= 上方:BUY STOP =================
   if(S[i].ceilv > 0 && !HoldingDir(i, POSITION_TYPE_BUY) && TimeCurrent() >= g_coolTo[i][0])
     {
      double price = NormalizeDouble(S[i].ceilv - Inp_BuyOffsetU * U, g_digits);
      double sl    = NormalizeDouble(price - S[i].slU * U, g_digits);
      double tp    = NormalizeDouble(price + S[i].tpU * U, g_digits);
      if(price > ask + StopDist())
         PlaceOrReplace(i, ORDER_TYPE_BUY_STOP, S[i].ceilv, price, sl, tp, newBar);
     }

   //================= 下方:SELL STOP ================
   if(S[i].floorv > 0 && !HoldingDir(i, POSITION_TYPE_SELL) && TimeCurrent() >= g_coolTo[i][1])
     {
      double price = NormalizeDouble(S[i].floorv + Inp_SellOffsetU * U, g_digits);
      double sl    = NormalizeDouble(price + S[i].slU * U, g_digits);
      double tp    = NormalizeDouble(price - S[i].tpU * U, g_digits);
      if(price < bid - StopDist())
         PlaceOrReplace(i, ORDER_TYPE_SELL_STOP, S[i].floorv, price, sl, tp, newBar);
     }
  }

//--- 该策略该方向是否已有持仓(占槽判定)
bool HoldingDir(int i, ENUM_POSITION_TYPE dir)
  {
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong tk = PositionGetTicket(p); if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != S[i].magic) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == dir) return true;
     }
   return false;
  }

void PlaceOrReplace(int i, ENUM_ORDER_TYPE type, double level, double price, double sl, double tp, bool newBar)
  {
   string cmt = Inp_TradeComment + "_Pending" + S[i].tag;
   ulong  cur = FindPending(S[i].magic, type);
   double ref = (type == ORDER_TYPE_BUY_STOP) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int    dix = (type == ORDER_TYPE_BUY_STOP) ? 0 : 1;

   // ★ 先算手数与预付款,再决定是否撤旧单。
   //   若把删单放在前面,一旦 CalcLots 返回 0 或预付款不足就会「删了不补」,该方向永久裸奔。
   double lots = CalcLots(MathAbs(price - sl));
   if(lots <= 0) return;
   if(Inp_MarginCheck && !MarginOK(type, lots, price)) return;

   // 槽位驱动补挂(平仓即挂,原版实测盈利平仓后 0 秒补挂);
   // 仅在「下单失败」后设 10 秒重试戳,防拒单刷屏。
   // ★ 节流检查必须在删旧单之前:否则替换路径会出现「删了旧单又被节流挡住不补」的裸奔窗
   static datetime failAt[GH_NSTRAT][2];
   if(TimeCurrent() - failAt[i][dix] < 10) return;

   // ★ V5.3 规则②: 槽位挂单节流 —— 距本槽上一次挂单(含替换)不足冷却分钟, 新挂与替换一律顺延。
   //   原版 2024+2025-26 共 5826 个相邻挂单间隔零违例; 被顺延的替换在「上次挂单 +15 分钟」那个 tick 执行。
   if(Inp_SlotThrottle && TimeCurrent() < g_slotTimer[i][dix])
     {
      if(newBar && cur != 0) g_defRep[i][dix] = true;   // 新K线的替换机会被节流挡住 → 登记, 节流到期后补做一次
      return;
     }

   bool replacing = false;
   if(cur != 0)
     {
      // V5.3: 被节流顺延的替换不再要求「恰好新K线」—— 节流到期后的首个 tick 补做一次
      //       (原版 12 例替换距上次挂单恰为 900 秒)。标记在此一次性消费, 绝不拖到后续盘中 tick。
      bool deferred = g_defRep[i][dix];
      g_defRep[i][dix] = false;
      // ★ 替换判定在「结构位」层面比较,而非挂单价。
      //   挂单价含 U(=0.2%×现价) 项,会随价格漂移逐根K线微移 0.0x,
      //   按挂单价比较会造成幽灵替换洪水(v2 实测 1019 次 vs 原版 167 次)。
      double curLvl = (dix == 0) ? S[i].armB : S[i].armS;
      if(curLvl > 0 && MathAbs(level - curLvl) < g_tick) return;   // 同一结构位 → 纹丝不动
      if(!newBar && !deferred) return;
      double old = OrderPriceOfTicket(cur);
      if(old <= 0) return;
      // 只向「更贴近现价」的新结构位替换(原版唯一替换路径)
      if(MathAbs(price - ref) >= MathAbs(old - ref) - g_tick * 0.5) return;
      PrintFormat("[%s] Closer entry detected, replacing %s #%I64u",
                  cmt, (type == ORDER_TYPE_BUY_STOP ? "buy stop" : "sell stop"), cur);
      replacing = true;
      // V5.2 顺序: 先删后挂。V5.3 规则⑤: 原版先挂新单再删旧单 → 删单挪到下单成功之后
      if(!Inp_PlaceThenDel && !trade.OrderDelete(cur)) return;
     }
   else
     {
      // ★ V5.3 规则④: 过期同位等新K线 —— 挂单在K线中途过期, 同一结构位在本根K线内不重挂
      //   (原版 2025-26: 3/54、2024: 0/48 当场重挂; 结构位已变则不受限, 当场挂出)
      if(Inp_ExpireWaitBar && g_expLvl[i][dix] > 0 && MathAbs(level - g_expLvl[i][dix]) < g_tick
         && S[i].lastBar == g_expBar[i][dix])
         return;
     }

   datetime exp = (g_ttype == ORDER_TIME_SPECIFIED) ? TimeCurrent() + S[i].expH * 3600 : 0;
   double   prevLvl   = (dix == 0) ? S[i].armB : S[i].armS;          // 失败回滚用
   datetime prevTimer = g_slotTimer[i][dix];
   trade.SetExpertMagicNumber(S[i].magic);
   if(trade.OrderOpen(_Symbol, type, lots, 0.0, price, sl, tp, g_ttype, exp, cmt))
     {
      ulong newTk = trade.ResultOrder();
      if(dix == 0) S[i].armB = level; else S[i].armS = level;      // 记录挂单背后的结构位
      if(Inp_SLCooldownMin > 0) g_slotTimer[i][dix] = TimeCurrent() + Inp_SLCooldownMin * 60;   // 规则②计时
      if(replacing && Inp_PlaceThenDel && !trade.OrderDelete(cur))
        {
         // 旧单删除失败 → 撤回新单并回滚登记, 绝不允许同槽双挂
         PrintFormat("[%s] 删除旧单 #%I64u 失败(rc=%d), 撤回新单 #%I64u", cmt, cur, trade.ResultRetcode(), newTk);
         if(newTk > 0) trade.OrderDelete(newTk);
         if(dix == 0) S[i].armB = prevLvl; else S[i].armS = prevLvl;
         g_slotTimer[i][dix] = prevTimer;
         failAt[i][dix] = TimeCurrent();
         return;
        }
      g_expLvl[i][dix]  = 0.0;                                      // 已重新布防 → 解除过期封锁
      g_defRep[i][dix]  = false;
      g_slotOrd[i][dix] = newTk;                                    // 同步挂单登记, 被替换的旧单不会被误判为过期
     }
   else
     {
      failAt[i][dix] = TimeCurrent();
      PrintFormat("[%s] OrderOpen failed rc=%d (%s) price=%s sl=%s tp=%s",
                  cmt, trade.ResultRetcode(), trade.ResultRetcodeDescription(),
                  DoubleToString(price, g_digits), DoubleToString(sl, g_digits), DoubleToString(tp, g_digits));
     }
  }

//--- GTC 模式下由 EA 自行按有效期回收超龄挂单(等价于服务器端 expiration)
void ExpireByAge()
  {
   if(g_ttype == ORDER_TIME_SPECIFIED) return;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i); if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      int si = StratIndexByMagic((long)OrderGetInteger(ORDER_MAGIC));
      if(si < 0 || S[si].expH <= 0) continue;      // expH<=0 视为永久有效,否则会秒删秒挂
      datetime setup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      if(TimeCurrent() - setup >= S[si].expH * 3600)
        {
         int d = ((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) ? 0 : 1;
         if(trade.OrderDelete(tk))
           {
            MarkExpired(si, d);                         // V5.3: EA 端到期等同服务器过期 → 同样登记过期同位封锁
            if(g_slotOrd[si][d] == tk) g_slotOrd[si][d] = 0;
           }
        }
     }
  }

//==================================================================//
//  追踪止损引擎 (对账 4252 条原版改单记录后的精确复刻)             //
//                                                                  //
//  两条并行的止损锚,取更紧者,只收紧不放松:                       //
//  ① 入场重锚: SL = 开仓价 ∓ (止损倍数×U + 实时点差)              //
//     — 成交同秒生效,处理滑点;点差收窄时会微量收紧(原版特征:     //
//       SL 以 0.002~0.006 逐 tick 微抖,即实时点差入公式的铁证)    //
//  ② 极值追踪: 买 SL = maxAsk − 追踪×U ; 卖 SL = minBid + 追踪×U   //
//     — 极值取「成交侧价格」(买单 Ask / 卖单 Bid),不加点差。       //
//       实证: E#387 fill 4039.643 → 首改 4031.227 = fill−1.0506U   //
//             C#388 fill 4039.643 → 首改 4031.631 = fill−0.999U    //
//             D#334 fill 4019.204 → 首改 4031.522 = fill+点差+1.5U //
//             (D 追踪 3.0U 劣于锚 → 首改为重锚,完全吻合)           //
//==================================================================//
void ManageTrailing()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spr = ask - bid;
   double U   = Unit();
   if(U <= 0) return;

   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong tk = PositionGetTicket(p);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long mg = PositionGetInteger(POSITION_MAGIC);
      int  si = StratIndexByMagic(mg);
      if(si < 0) continue;
      // 登记簿键统一用 POSITION_IDENTIFIER(与平仓 deal 的 DEAL_POSITION_ID 同命名空间,
      // 服务性再开仓后 ticket 会变而 identifier 不变,避免登记簿泄漏)
      ulong pid = (ulong)PositionGetInteger(POSITION_IDENTIFIER);

      long   type  = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double newSL;

      if(type == POSITION_TYPE_BUY)
        {
         double trailv = TrackTrail(pid, bid, true, open, U, S[si].trU, S[si].trStart);  // ② Bid 新高时定价
         double anchor = open - spr - S[si].slU * U;      // ① 入场重锚(含实时点差, 每 tick)
         newSL = NormalizeDouble(MathMax(anchor, trailv), g_digits);
         if(newSL > bid - StopDist()) continue;
         if(curSL > 0 && newSL <= curSL + g_tick * 0.5) continue;
        }
      else
        {
         double trailv = TrackTrail(pid, ask, false, open, U, S[si].trU, S[si].trStart); // ② Ask 新低时定价
         double anchor = open + spr + S[si].slU * U;
         newSL = NormalizeDouble(MathMin(anchor, trailv), g_digits);
         if(newSL < ask + StopDist()) continue;
         if(curSL > 0 && newSL >= curSL - g_tick * 0.5) continue;
        }
      trade.SetExpertMagicNumber(mg);
      trade.PositionModify(tk, newSL, curTP);
     }
  }

//--- V5.2 极值追踪登记簿(原版机制, 逐 tick 对账 98.0%):
//    买单跟踪 Bid 的运行最高、卖单跟踪 Ask 的运行最低;只有出现「新极值」的那个 tick 才用当时的 U
//    重算追踪候选价 = 极值 ∓ 追踪倍数×U, 且须浮盈达到启动门槛(极值相对开仓价 ≥ 门槛×U)。
//    其余 tick 沿用上次候选价 —— 不随 U(价格)漂移, 这正是 V5 止损偏紧的根源。
//    返回值: 买单无有效候选 = -DBL_MAX, 卖单 = +DBL_MAX(由入场重锚接管)。
double TrackTrail(ulong tk, double px, bool isBuy, double open, double U, double trU, double trStart)
  {
   int j = -1;
   for(int k = 0; k < g_ntrk; k++) if(g_trk[k].tk == tk) { j = k; break; }
   bool newExt = false;
   if(j < 0)
     {
      if(g_ntrk >= 64) TrackGC();                 // 满表先回收死仓(手动平仓等路径的泄漏)
      if(g_ntrk >= 64) return(isBuy ? -DBL_MAX : DBL_MAX);
      j = g_ntrk++;
      g_trk[j].tk = tk; g_trk[j].m = px; newExt = true;
     }
   else if(isBuy ? (px > g_trk[j].m) : (px < g_trk[j].m)) { g_trk[j].m = px; newExt = true; }
   if(newExt)
     {
      double fav = isBuy ? (g_trk[j].m - open) : (open - g_trk[j].m);
      if(fav >= trStart * U) g_trk[j].trs = isBuy ? g_trk[j].m - trU * U : g_trk[j].m + trU * U;
      else                   g_trk[j].trs = isBuy ? -DBL_MAX : DBL_MAX;
     }
   return(g_trk[j].trs);
  }

//--- 登记簿垃圾回收:清掉已不存在的持仓条目
void TrackGC()
  {
   for(int j = g_ntrk - 1; j >= 0; j--)
     {
      bool live = false;
      for(int p = PositionsTotal() - 1; p >= 0 && !live; p--)
         if(PositionGetTicket(p) > 0 &&
            (ulong)PositionGetInteger(POSITION_IDENTIFIER) == g_trk[j].tk) live = true;
      if(!live) { g_trk[j] = g_trk[g_ntrk - 1]; g_ntrk--; }
     }
  }

//--- 平仓后从登记簿移除
void TrackDrop(ulong tk)
  {
   for(int j = 0; j < g_ntrk; j++)
      if(g_trk[j].tk == tk)
        {
         g_trk[j] = g_trk[g_ntrk - 1];
         g_ntrk--;
         return;
        }
  }

//==================================================================//
//                            风控模块                              //
//==================================================================//
void RefreshRisk()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEquity) g_peakEquity = eq;

   datetime ds = DayStamp(TimeCurrent());
   if(ds != g_dayStamp)
     {
      g_dayStamp   = ds;
      g_dayStartEq = eq;
      if(g_haltDaily) { g_halted = false; g_haltDaily = false;   // 「单日」回撤必须每日复位
                        PrintFormat("[%s] Daily DD halt released", Inp_TradeComment); }
     }

   double base = Inp_DDAccountWide ? eq : (AccountInfoDouble(ACCOUNT_BALANCE) + MyFloatingPL());

   if(Inp_MaxDrawdownPct > 0 && g_peakEquity > 0)
      if((g_peakEquity - base) / g_peakEquity * 100.0 >= Inp_MaxDrawdownPct) Halt("MaxDD");

   if(Inp_DailyDDPct > 0 && g_dayStartEq > 0)
      if((g_dayStartEq - base) / g_dayStartEq * 100.0 >= Inp_DailyDDPct) Halt("DailyDD");
  }

//--- 新闻窗口:重活(日历库查询)每秒最多一次,判定结果缓存供 TradingAllowed 读取
void RefreshNews()
  {
   static datetime stamp = 0;
   if(!Inp_UseNewsFilter) { g_newsBlock = false; return; }
   if(TimeCurrent() == stamp) return;
   stamp = TimeCurrent();
   bool was = g_newsBlock;
   g_newsBlock = InNewsWindow();
   if(g_newsBlock && !was && Inp_DeleteOnNews) PurgeMyPendings();   // 只在进入窗口的那一刻删一次
  }

void PurgeMyPendings()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i); if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(IsMine((long)OrderGetInteger(ORDER_MAGIC))) trade.OrderDelete(tk);
     }
  }

void Halt(string why)
  {
   if(why != "DailyDD") g_haltDaily = false;  // 任何非单日原因(含由单日升级为总回撤) → 取消次日自动复位
   if(g_halted) return;
   g_halted = true;
   if(why == "DailyDD") g_haltDaily = true;   // 单日回撤熔断 → 次日自动解除
   PrintFormat("[%s] RISK HALT (%s) — closing %s", Inp_TradeComment, why,
               (Inp_CloseAll ? "ALL account positions & pendings" : "this EA only"));
   CloseEverything(Inp_CloseAll);
  }

void CloseEverything(bool accountWide)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i); if(tk == 0) continue;
      if(!accountWide)
        {
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         if(!IsMine((long)OrderGetInteger(ORDER_MAGIC))) continue;
        }
      trade.OrderDelete(tk);
     }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i); if(tk == 0) continue;
      if(!accountWide)
        {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(!IsMine(PositionGetInteger(POSITION_MAGIC))) continue;
        }
      trade.PositionClose(tk);
     }
  }

//--- 交易许可总闸
bool TradingAllowed()
  {
   if(g_halted) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))           return false;
   // (冷却已改为分槽制,在 ArmPendings 内按 策略×方向 各自判定)
   if(SpreadPoints() > Inp_MaxSpreadPts)            return false;
   if(g_newsBlock)                                  return false;

   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(Inp_WeekendClose)
     {
      if(t.day_of_week == 5 && g_fridayNoEntry > 0 && t.hour >= g_fridayNoEntry) return false;
      // V5.1: 周日开盘不封锁(原版周日 22:05/23:05 首个 tick 即布防, 全期 540 张); 只封周一 0 点小时段
      if(t.day_of_week == 1 && Inp_MondayResume > 0 && t.hour < Inp_MondayResume)   return false;
     }
   if(Inp_ConservativeMode && MyPositions() >= 2) return false;
   return true;
  }

void ManageWeekend()
  {
   if(!Inp_WeekendClose) return;
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(t.day_of_week != 5) return;
   if(Inp_FridayDelPend > 0 && t.hour >= Inp_FridayDelPend) PurgeMyPendings();
   if(Inp_FridayClosePos > 0 && t.hour >= Inp_FridayClosePos)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i); if(tk == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(IsMine(PositionGetInteger(POSITION_MAGIC))) trade.PositionClose(tk);
        }
  }

//--- 平仓事件: 只做追踪登记簿清理(实盘异步路径的兜底)。
//    V5.1: 冷却判定已移入 OnTick 开头的 SyncSlots() —— 测试器中本函数晚于 OnTick 触发,
//    V5 在这里写冷却戳会让「亏损平仓 → 同 tick 立即补挂」漏网(全样本 254 次)。
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   long mg = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(!IsMine(mg)) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   TrackDrop((ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));   // 清极值登记
  }

//==================================================================//
//  V5.1 槽位同步 + 亏损冷却(原版铁律: 亏损平仓 → 该槽 900 秒后补挂;  //
//  盈利/保本平仓 → 0 秒补挂)。在 OnTick 最前面执行, 与测试器事件顺序无关 //
//==================================================================//
void SyncSlots()
  {
   ulong cur[GH_NSTRAT][2];
   for(int i = 0; i < GH_NSTRAT; i++) { cur[i][0] = 0; cur[i][1] = 0; }
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong tk = PositionGetTicket(p);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      int si = StratIndexByMagic(PositionGetInteger(POSITION_MAGIC));
      if(si < 0) continue;
      int d = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 0 : 1;
      if(cur[si][d] == 0) cur[si][d] = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
     }
   for(int i = 0; i < GH_NSTRAT; i++)
      for(int d = 0; d < 2; d++)
        {
         if(g_slotPid[i][d] != 0 && g_slotPid[i][d] != cur[i][d]) OnSlotClosed(i, d, g_slotPid[i][d]);
         g_slotPid[i][d] = cur[i][d];
        }
  }

//==================================================================//
//  V5.3 挂单同步(规则④): 识别「本槽挂单因到期而消失」, 登记过期同位封锁 //
//  必须在策略循环更新 S[i].lastBar 之前执行: 若过期恰好发生在新K线首个 //
//  tick(到期时刻 = K线开盘), 登记的是上一根K线 → 本 tick 即视为新K线, //
//  同位立即重挂(原版 exp@bar 同位当场重挂 129/135); 盘中过期则封锁到 //
//  下一根K线开盘(原版 exp@mid 同位当场重挂 3/102)。                   //
//==================================================================//
void SyncOrders()
  {
   for(int i = 0; i < GH_NSTRAT; i++)
     {
      if(!S[i].on) continue;
      for(int d = 0; d < 2; d++)
        {
         ulong cur  = FindPending(S[i].magic, (d == 0) ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP);
         ulong prev = g_slotOrd[i][d];
         if(prev != 0 && prev != cur)
           {
            g_defRep[i][d] = false;                     // 旧挂单已不在 → 待补替换作废
            if(HistoryOrderSelect(prev) &&
               (ENUM_ORDER_STATE)HistoryOrderGetInteger(prev, ORDER_STATE) == ORDER_STATE_EXPIRED)
               MarkExpired(i, d);
           }
         g_slotOrd[i][d] = cur;
        }
     }
  }

//--- 登记过期同位封锁: 封锁的是「过期挂单背后的结构位」, 到本策略周期下一根K线开盘解除
void MarkExpired(int i, int d)
  {
   g_expLvl[i][d] = (d == 0) ? S[i].armB : S[i].armS;
   g_expBar[i][d] = S[i].lastBar;
  }

//--- 某槽持仓已消失: 汇总该持仓全部出场成交的净盈亏, 亏损则从出场时刻起冷却
void OnSlotClosed(int si, int d, ulong pid)
  {
   TrackDrop(pid);
   if(Inp_SLCooldownMin <= 0) return;
   if(!HistorySelectByPosition((long)pid)) return;
   double   pnl  = 0.0;
   datetime tOut = 0;
   bool     out  = false;
   int n = HistoryDealsTotal();
   for(int k = 0; k < n; k++)
     {
      ulong dl = HistoryDealGetTicket(k);
      if(dl == 0) continue;
      ENUM_DEAL_ENTRY en = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dl, DEAL_ENTRY);
      if(en != DEAL_ENTRY_OUT && en != DEAL_ENTRY_OUT_BY && en != DEAL_ENTRY_INOUT) continue;
      out  = true;
      pnl += HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP)
           + HistoryDealGetDouble(dl, DEAL_COMMISSION);
      datetime t = (datetime)HistoryDealGetInteger(dl, DEAL_TIME);
      if(t > tOut) tOut = t;
     }
   if(!out || pnl >= 0) return;                       // 盈利/保本平仓 → 不冷却, 立即补挂
   if(tOut <= 0) tOut = TimeCurrent();
   // ★ V5.3 规则③: 亏损冷却锚定 —— 亏损发生时本槽挂单节流尚未到期(挂单→平仓 <冷却期),
   //   原版不再追加「平仓 +冷却」, 下一单在「上次挂单 +冷却」挂出(46/58 例); 否则按平仓起算(579 例)。
   if(Inp_LossAnchor && Inp_SlotThrottle && tOut < g_slotTimer[si][d]) return;
   datetime until = tOut + Inp_SLCooldownMin * 60;
   if(until > g_coolTo[si][d]) g_coolTo[si][d] = until;
  }

//--- 新闻窗口(占位:内置日历接口,无日历权限时恒为 false)
bool InNewsWindow()
  {
   MqlCalendarValue vals[];
   datetime from = TimeCurrent() - Inp_NewsMinAfter  * 60;
   datetime to   = TimeCurrent() + Inp_NewsMinBefore * 60;
   if(CalendarValueHistory(vals, from, to, NULL, "USD") > 0)
      for(int i = 0; i < ArraySize(vals); i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id, ev)) continue;
         if(ev.importance == CALENDAR_IMPORTANCE_HIGH) return true;   // 纯判定,无副作用
        }
   return false;
  }

//==================================================================//
//                            手数计算                              //
//==================================================================//
double CalcLots(double slDist)
  {
   double lots = Inp_FixedLots;
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);

   switch(Inp_LotMode)
     {
      case LOT_FIXED:   lots = Inp_FixedLots;                                    break;
      case LOT_BALANCE: lots = Inp_LotsPerStep   * MathFloor(bal / 2000.0);      break;
      case LOT_EQUITY:  lots = Inp_LotsPerStep   * MathFloor(eq  / 2000.0);      break;
      case LOT_MARGIN:  lots = Inp_MarginLotStep * MathFloor(g_startMargin / 2000.0); break;
      case LOT_RISK:
        {
         double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         if(tickVal <= 0 || g_tick <= 0 || slDist <= 0) { lots = Inp_FixedLots; break; }
         double riskCash = bal * Inp_RiskPct / 100.0 * (AutoRate ? g_exRate : Inp_ExchangeRate);
         double lossPer1 = slDist / g_tick * tickVal;
         lots = (lossPer1 > 0) ? riskCash / lossPer1 : Inp_FixedLots;
         break;
        }
     }
   lots = MathMin(lots, g_maxLot);
   if(Inp_MaxLotSize > 0) lots = MathMin(lots, Inp_MaxLotSize);
   if(g_lotStep > 0) lots = MathFloor(lots / g_lotStep + 1e-8) * g_lotStep;
   // 资金不足以支撑最小手 → 明确不下单(不再静默抬到 g_minLot,
   // 否则「每 2000 美元一档」的资金门槛会被作废)。首次发生时告警一次,杜绝静默失效。
   if(lots < g_minLot - 1e-8)
     {
      static bool warned = false;
      if(!warned)
        {
         warned = true;
         PrintFormat("[%s] CalcLots=%.4f < minLot=%.4f → 暂停下单(请检查 LotMode / FixedLots / MaxLotSize / 结余)",
                     Inp_TradeComment, lots, g_minLot);
        }
      return 0.0;
     }
   if(g_lotStep > 0) lots = MathRound(lots / g_lotStep) * g_lotStep;   // 非十进制步长(0.25等)防脱网格
   return NormalizeDouble(lots, g_lotDigits);
  }

bool MarginOK(ENUM_ORDER_TYPE type, double lots, double price)
  {
   double need = 0.0;
   ENUM_ORDER_TYPE mt = (type == ORDER_TYPE_BUY_STOP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(mt, _Symbol, lots, price, need)) return true;
   double freeM = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double keep  = AccountInfoDouble(ACCOUNT_BALANCE) * Inp_MarginReservePct / 100.0;
   return (freeM - need >= keep);
  }

double CalcExchangeRate()
  {
   string acc = AccountInfoString(ACCOUNT_CURRENCY);
   string prof= SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   if(!AutoRate) return Inp_ExchangeRate;
   if(acc == prof) return 1.0;
   double b = 0;
   if(SymbolInfoDouble(prof + acc, SYMBOL_BID, b) && b > 0) return b;
   if(SymbolInfoDouble(acc + prof, SYMBOL_BID, b) && b > 0) return 1.0 / b;
   return Inp_ExchangeRate;
  }

//==================================================================//
//                            工具函数                              //
//==================================================================//
double Unit()
  {
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK) * Inp_UnitPct;   // V5.2: 原版以 Ask 为基准(4207/4211 张挂单逐位复现)
  }

double StopDist()
  {
   return MathMax(g_stopLvl * g_point, g_tick);
  }

double SpreadPoints()
  {
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
  }

bool IsMine(long magic)
  {
   for(int i = 0; i < GH_NSTRAT; i++) if(magic == S[i].magic) return true;
   return (magic == Inp_BaseMagic);
  }

int StratIndexByMagic(long magic)
  {
   for(int i = 0; i < GH_NSTRAT; i++) if(magic == S[i].magic) return i;
   return -1;
  }

ulong FindPending(long magic, ENUM_ORDER_TYPE type)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i); if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != magic)   continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type) continue;
      return tk;
     }
   return 0;
  }

double OrderPriceOfTicket(ulong tk)
  {
   if(!OrderSelect(tk)) return 0.0;
   return OrderGetDouble(ORDER_PRICE_OPEN);
  }

int MyPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i); if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && IsMine(PositionGetInteger(POSITION_MAGIC))) n++;
     }
   return n;
  }

int MyPendings()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i); if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && IsMine((long)OrderGetInteger(ORDER_MAGIC))) n++;
     }
   return n;
  }

double MyFloatingPL()
  {
   double s = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i); if(tk == 0) continue;
      if(!IsMine(PositionGetInteger(POSITION_MAGIC))) continue;
      s += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }
   return s;
  }

datetime DayStamp(datetime t) { return (datetime)(t / 86400 * 86400); }

datetime g_lastDaily = 0;
void DailyCheckLog()
  {
   datetime d = DayStamp(TimeCurrent());
   if(d == g_lastDaily) return;
   g_lastDaily = d;
   PrintFormat("===== [Daily Check] %s | %s =====", Inp_TradeComment,
               TimeToString(TimeCurrent(), TIME_DATE));
   PrintFormat("  Symbol: %s | Trade: %s", _Symbol, (TradingAllowed() ? "ON" : "OFF"));
   PrintFormat("  Balance: %.2f | Equity: %.2f | Open Positions: %d | Pending Orders: %d",
               AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY),
               MyPositions(), MyPendings());
  }

//==================================================================//
//                        边界线 & 汇总统计                         //
//==================================================================//
void CollectBoundary()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_uiCeil = 0; g_uiFloor = 0; g_uiCeilOrd = 0; g_uiFloorOrd = 0;
   g_uiCeilLot = 0; g_uiFloorLot = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i); if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(!IsMine((long)OrderGetInteger(ORDER_MAGIC))) continue;
      ENUM_ORDER_TYPE ty = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double p = OrderGetDouble(ORDER_PRICE_OPEN);
      double v = OrderGetDouble(ORDER_VOLUME_CURRENT);
      if(ty == ORDER_TYPE_BUY_STOP && p > ask)
        { if(g_uiCeil == 0 || p < g_uiCeil) { g_uiCeil = p; g_uiCeilLot = v; } g_uiCeilOrd++; }
      if(ty == ORDER_TYPE_SELL_STOP && p < bid)
        { if(g_uiFloor == 0 || p > g_uiFloor) { g_uiFloor = p; g_uiFloorLot = v; } g_uiFloorOrd++; }
     }
  }

void DrawBoundary()
  {
   CollectBoundary();
   HLine(GH_PFX + "UP", g_uiCeil,  Inp_UpperLineClr);
   HLine(GH_PFX + "DN", g_uiFloor, Inp_LowerLineClr);
  }

void DeleteBoundary()
  {
   ObjectDelete(0, GH_PFX + "UP");
   ObjectDelete(0, GH_PFX + "DN");
  }

void HLine(string nm, double price, color clr)
  {
   if(price <= 0) { ObjectDelete(0, nm); return; }
   if(ObjectFind(0, nm) < 0)
     {
      ObjectCreate(0, nm, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
     }
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetDouble(0, nm, OBJPROP_PRICE, price);
  }

//==================================================================//
//                    UI 面板 (逐像素取色复刻)                      //
//   取色来源: UI面板.png  →  见《UI面板取色对照.html》              //
//==================================================================//
#define C_BG      C'6,8,16'         // 面板底 #060810
#define C_HEADBG  C'10,16,28'       // 标题栏底 #0A101C
#define C_BORDER  C'14,34,48'       // 描边
#define C_LABEL   C'70,90,110'      // 标签灰蓝 #465A6E
#define C_VALUE   C'180,200,220'    // 数值浅蓝白 #B4C8DC
#define C_CYAN    C'0,230,230'      // 主青 #00E6E6
#define C_CYAN2   C'0,190,190'      // 次青 #00BEBE
#define C_GREEN   C'0,230,120'      // 在线绿 #00E678
#define C_TEAL    C'0,180,200'      // CEILING 标签 #00B4C8
#define C_MAG     C'200,40,255'     // FLOOR 值 #C828FF
#define C_MAG2    C'180,40,220'     // FLOOR 标签 #B428DC
#define C_GREY    C'60,85,100'      // 细节灰 #3C5564
#define C_SEP     C'18,30,44'       // 分隔线

#define PX 20                        // 面板左上角 X
#define PY 26                        // 面板左上角 Y
#define PW 266                       // 面板宽
#define FONT "Consolas"

int  g_rowY[24];

void Lbl(string nm, int x, int y, string txt, color clr, int size = 8, string fnt = FONT, ENUM_ANCHOR_POINT anc = ANCHOR_LEFT_UPPER)
  {
   string o = GH_PFX + nm;
   if(ObjectFind(0, o) < 0)
     {
      ObjectCreate(0, o, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, o, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, o, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, o, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, o, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, o, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, o, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, o, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, o, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, o, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, o, OBJPROP_FONT, fnt);
   ObjectSetString(0, o, OBJPROP_TEXT, txt);
  }

void Rect(string nm, int x, int y, int w, int h, color bg, color bd)
  {
   string o = GH_PFX + nm;
   if(ObjectFind(0, o) < 0)
     {
      ObjectCreate(0, o, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, o, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, o, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, o, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, o, OBJPROP_BACK, false);
      ObjectSetInteger(0, o, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, o, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, o, OBJPROP_WIDTH, 1);
     }
   ObjectSetInteger(0, o, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, o, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, o, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, o, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, o, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, o, OBJPROP_COLOR, bd);
  }

void BuildPanel()
  {
   //---- 顶部状态条(图表左上角)
   Lbl("sys", 6, 4, "▤ ▦ SYSTEM ONLINE", C_CYAN2, 8);

   //---- 面板主体
   Rect("bg",   PX, PY,      PW, 322, C_BG,     C_BORDER);
   Rect("head", PX, PY,      PW,  28, C_HEADBG, C_BORDER);

   //---- 标题栏
   Lbl("dot",   PX + 10, PY + 7,  "●",           C_GREEN, 8);
   Lbl("onln",  PX + 24, PY + 8,  "ONLINE",      C_CYAN2, 8);
   Lbl("dia1",  PX + 74, PY + 8,  "◆",           C_CYAN,  8);
   Lbl("ttl",   PX + 88, PY + 8,  "GOLD HOUSE",  C_CYAN,  8);
   Lbl("dia2",  PX +186, PY + 8,  "◆",           C_CYAN,  8);
   Lbl("ver",   PX +202, PY + 8,  GH_VERSION,    C_CYAN2, 8);

   //---- 行标签(左列)
   int y = PY + 44;  int st = 19;
   Lbl("l1", PX + 10, y,          "BALANCE",   C_LABEL);
   Lbl("l2", PX + 10, y + st,     "EQUITY",    C_LABEL);
   Lbl("l3", PX + 10, y + st * 2, "P / L",     C_LABEL);
   Rect("s1", PX + 8, y + st * 3 + 4, PW - 16, 1, C_SEP, C_SEP);
   Lbl("l4", PX + 10, y + st * 3 + 12,     "SPREAD",   C_LABEL);
   Lbl("l5", PX + 10, y + st * 4 + 12,     "BID",      C_LABEL);
   Lbl("l6", PX + 10, y + st * 5 + 12,     "ASK",      C_LABEL);
   Rect("s2", PX + 8, y + st * 6 + 16, PW - 16, 1, C_SEP, C_SEP);
   Lbl("l7", PX + 10, y + st * 6 + 24,     "PENDING",   C_LABEL);
   Lbl("l8", PX + 10, y + st * 7 + 24,     "POSITIONS", C_LABEL);
   Rect("s3", PX + 8, y + st * 8 + 28, PW - 16, 1, C_SEP, C_SEP);
   Lbl("l9", PX + 10, y + st * 8 + 36,     "▲CEILING",  C_TEAL);
   Lbl("l10",PX + 10, y + st * 9 + 36,     "▼FLOOR",    C_MAG2);
   Rect("s4", PX + 8, y + st *10 + 40, PW - 16, 1, C_SEP, C_SEP);
   Lbl("l11",PX + 10, y + st *10 + 48,     "TERMINAL",  C_LABEL);
   Lbl("l12",PX + 10, y + st *11 + 48,     "EA TRADE",  C_LABEL);

   for(int i = 0; i < 12; i++)
     {
      int add = (i < 3) ? 0 : (i < 6 ? 12 : (i < 8 ? 24 : (i < 10 ? 36 : 48)));
      g_rowY[i] = y + st * i + add;
     }
  }

void UpdatePanel()
  {
   CollectBoundary();
   int R = PX + PW - 10;                         // 右对齐基准
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pl  = MyFloatingPL();

   Lbl("v1", R, g_rowY[0], DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), C_VALUE, 8, FONT, ANCHOR_RIGHT_UPPER);
   Lbl("v2", R, g_rowY[1], DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),  C_VALUE, 8, FONT, ANCHOR_RIGHT_UPPER);
   Lbl("v3", R, g_rowY[2], (pl >= 0 ? "+" : "") + DoubleToString(pl, 2),
       (pl >= 0 ? C_GREEN : C_MAG), 8, FONT, ANCHOR_RIGHT_UPPER);

   Lbl("v4", R, g_rowY[3], DoubleToString((ask - bid) / g_pip, 1),     C_CYAN2, 8, FONT, ANCHOR_RIGHT_UPPER);
   Lbl("v5", R, g_rowY[4], DoubleToString(bid, g_digits),              C_VALUE, 8, FONT, ANCHOR_RIGHT_UPPER);
   Lbl("v6", R, g_rowY[5], DoubleToString(ask, g_digits),              C_VALUE, 8, FONT, ANCHOR_RIGHT_UPPER);

   Lbl("v7", R, g_rowY[6], IntegerToString(MyPendings()),              C_CYAN2, 8, FONT, ANCHOR_RIGHT_UPPER);
   Lbl("v8", R, g_rowY[7], IntegerToString(MyPositions()),             C_CYAN2, 8, FONT, ANCHOR_RIGHT_UPPER);

   Lbl("v9", R, g_rowY[8], (g_uiCeil  > 0 ? DoubleToString(g_uiCeil,  g_digits) : "-----"), C_CYAN, 8, FONT, ANCHOR_RIGHT_UPPER);
   Lbl("v10",R, g_rowY[9], (g_uiFloor > 0 ? DoubleToString(g_uiFloor, g_digits) : "-----"), C_MAG,  8, FONT, ANCHOR_RIGHT_UPPER);

   bool tOK = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   bool eOK = TradingAllowed();
   Lbl("v11",R, g_rowY[10], (tOK ? "ON" : "OFF"), (tOK ? C_GREEN : C_MAG), 8, FONT, ANCHOR_RIGHT_UPPER);
   Lbl("v12",R, g_rowY[11], (eOK ? "ON" : "OFF"), (eOK ? C_GREEN : C_MAG), 8, FONT, ANCHOR_RIGHT_UPPER);

   UpdateNearCard(bid, ask);
   ChartRedraw();
  }

//---- 底部「最近上/下挂单」双栏卡片
void UpdateNearCard(double bid, double ask)
  {
   int W = 440, H = 68;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int x = (cw - W) / 2 + 60;
   int y = ch - 300; if(y < PY + 340) y = PY + 340;

   Rect("cbg", x, y, W, H, C_BG, C_BORDER);
   Rect("cmid", x + W / 2, y + 6, 1, H - 12, C_SEP, C_SEP);

   Lbl("c1", x + 12,        y + 8,  "▲NEAREST ABOVE", C_TEAL, 8);
   Lbl("c2", x + W / 2 + 12, y + 8,  "▼NEAREST BELOW", C_MAG2, 8);

   Lbl("c3", x + 12,        y + 26,
       (g_uiCeil  > 0 ? DoubleToString(g_uiCeil,  g_digits) : "---.---"), C_CYAN, 11);
   Lbl("c4", x + W / 2 + 12, y + 26,
       (g_uiFloor > 0 ? DoubleToString(g_uiFloor, g_digits) : "---.---"), C_MAG,  11);

   Lbl("c5", x + W / 2 - 12, y + 26, "BUY STOP",  C_TEAL, 8, FONT, ANCHOR_RIGHT_UPPER);
   Lbl("c6", x + W    - 12,  y + 26, "SELL STOP", C_MAG2, 8, FONT, ANCHOR_RIGHT_UPPER);

   string d1 = (g_uiCeil  > 0) ? StringFormat("%.1f pip  |  %.2f lot  |  %d ord",
                                              (g_uiCeil - ask) / g_pip, g_uiCeilLot, g_uiCeilOrd) : "--";
   string d2 = (g_uiFloor > 0) ? StringFormat("%.1f pip  |  %.2f lot  |  %d ord",
                                              (bid - g_uiFloor) / g_pip, g_uiFloorLot, g_uiFloorOrd) : "--";
   Lbl("c7", x + 12,        y + 48, d1, C_GREY, 8);
   Lbl("c8", x + W / 2 + 12, y + 48, d2, C_GREY, 8);
  }
//+------------------------------------------------------------------+

//==================================================================//
//  V5.1 · OnTester 复刻                                             //
//  原版回测报告「OnTester结果 = 14415.35」(复刻版 V5 为 0)。          //
//  反解: 盈利因子 1.96608 × 采收率 16.16289 × 夏普 10.78 × √1771     //
//        = 14415(夏普显示值四舍五入区间内精确命中)。只影响优化排序。  //
//==================================================================//
double OnTester()
  {
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double rf = TesterStatistics(STAT_RECOVERY_FACTOR);
   double sh = TesterStatistics(STAT_SHARPE_RATIO);
   double tr = TesterStatistics(STAT_TRADES);
   if(tr <= 0) return(0.0);
   return(pf * rf * sh * MathSqrt(tr));
  }

//==================================================================//
//  V5.1 · 模块对接层 (全部只读状态 / 人工指令, 不参与策略判定)      //
//==================================================================//
string GH_Sgn(double v)       { return((v >= 0 ? "+" : "-") + DoubleToString(MathAbs(v), 2)); }
string GH_Px(double v)        { return(v > 0 ? DoubleToString(v, g_digits) : "—"); }
bool   GH_IsManual(long mg)   { return(mg == Inp_RC_ManualMagic); }
bool   GH_IsEAPos(long mg)    { return(IsMine(mg) || GH_IsManual(mg)); }

string GH_Clock(long sec)
  {
   if(sec < 0) sec = 0;
   if(sec >= 3600) return(StringFormat("%dh%02dm", (int)(sec / 3600), (int)((sec % 3600) / 60)));
   return(StringFormat("%02d:%02d", (int)(sec / 60), (int)(sec % 60)));
  }

//--- 当前不能布防的原因(与 TradingAllowed 同序; 仅显示用)
string GH_BlockReason()
  {
   if(g_uiPaused)                                     return("面板暂停中(只停新挂单)");
   if(RC_BlockNew())                                  return("遥控: 停开新挂单");
   if(g_halted)                                       return("回撤熔断已触发");
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))   return("终端未允许自动交易");
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))             return("EA 未获交易许可");
   if(SpreadPoints() > Inp_MaxSpreadPts)              return(StringFormat("点差 %.0f 点 > 上限 %.0f", SpreadPoints(), Inp_MaxSpreadPts));
   if(g_newsBlock)                                    return("新闻窗口封锁");
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(Inp_WeekendClose)
     {
      if(t.day_of_week == 5 && g_fridayNoEntry > 0 && t.hour >= g_fridayNoEntry)
         return(StringFormat("周五 %d 点后停止新挂单", g_fridayNoEntry));
      if(t.day_of_week == 1 && Inp_MondayResume > 0 && t.hour < Inp_MondayResume)
         return(StringFormat("周一 %d 点前暂停挂单", Inp_MondayResume));
     }
   if(Inp_ConservativeMode && MyPositions() >= 2)     return("保守模式: 持仓已达 2 张");
   return("");
  }

//--- 手数规整(人工单用)
double GH_NormLots(double v)
  {
   double st = (g_lotStep > 0) ? g_lotStep : 0.01;
   v = MathFloor(v / st + 1e-8) * st;
   if(v < g_minLot) v = g_minLot;
   if(g_maxLot > 0 && v > g_maxLot) v = g_maxLot;
   return(NormalizeDouble(v, g_lotDigits));
  }

//--- 人工开仓(面板按钮/遥控): 独立魔术号, 按 A 策略几何带服务器止损止盈, 不进入策略占槽
bool GH_ManualOpen(bool buy, double lots, string src)
  {
   double U = Unit();
   if(U <= 0) return(false);
   lots = GH_NormLots(lots);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double px  = buy ? ask : bid;
   double sl  = NormalizeDouble(buy ? px - S[0].slU * U : px + S[0].slU * U, g_digits);
   double tp  = NormalizeDouble(buy ? px + S[0].tpU * U : px - S[0].tpU * U, g_digits);
   trade.SetExpertMagicNumber(Inp_RC_ManualMagic);
   string cmt = Inp_TradeComment + "_Manual";
   bool ok = buy ? trade.Buy(lots, _Symbol, 0.0, sl, tp, cmt) : trade.Sell(lots, _Symbol, 0.0, sl, tp, cmt);
   g_uiLastAct = StringFormat("%s人工%s %.2f手 %s", src, (buy ? "开多" : "开空"), lots,
                              (ok ? "成功" : "失败 rc=" + IntegerToString((int)trade.ResultRetcode())));
   PrintFormat("[%s] %s", Inp_TradeComment, g_uiLastAct);
   if(g_uiLive) UiLog(g_uiLastAct);
   return(ok);
  }

//--- 平本EA持仓: side -1=全部 / 0=多 / 1=空 (策略单 + 人工单)
int GH_CloseSide(int side)
  {
   int n = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong tk = PositionGetTicket(p);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!GH_IsEAPos(PositionGetInteger(POSITION_MAGIC))) continue;
      int d = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 0 : 1;
      if(side >= 0 && d != side) continue;
      if(trade.PositionClose(tk)) n++;
     }
   return(n);
  }

bool GH_HasSide(int side)
  {
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong tk = PositionGetTicket(p);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!GH_IsEAPos(PositionGetInteger(POSITION_MAGIC))) continue;
      int d = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 0 : 1;
      if(d == side) return(true);
     }
   return(false);
  }

//--- 保本: 浮盈单止损移到开仓价(只收紧) / 浮亏单止盈移到开仓价(回本即走)
int GH_BreakEven()
  {
   int n = 0;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sd  = StopDist();
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong tk = PositionGetTicket(p);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long mg = PositionGetInteger(POSITION_MAGIC);
      if(!GH_IsEAPos(mg)) continue;
      bool   buy  = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), g_digits);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double nsl  = sl, ntp = tp;
      if(buy)
        {
         if(bid - open > sd)      { if(sl < open - g_tick * 0.5) nsl = open; }
         else if(open - bid > sd) { ntp = open; }
        }
      else
        {
         if(open - ask > sd)      { if(sl <= 0 || sl > open + g_tick * 0.5) nsl = open; }
         else if(ask - open > sd) { ntp = open; }
        }
      if(MathAbs(nsl - sl) < g_tick * 0.5 && MathAbs(ntp - tp) < g_tick * 0.5) continue;
      trade.SetExpertMagicNumber(mg);
      if(trade.PositionModify(tk, nsl, ntp)) n++;
     }
   return(n);
  }

//--- 遥控轮询(回测中 RC_Poll 立即返回 -1, 零开销)
void GH_RemoteControl()
  {
   int a = RC_Poll();
   if(a >= 0)
     {
      string r = "";
      switch(a)
        {
         case RC_CMD_OPEN_BUY:   r = GH_ManualOpen(true,  Inp_RC_ManualLots, "遥控") ? "已强制开多" : "开多失败"; break;
         case RC_CMD_OPEN_SELL:  r = GH_ManualOpen(false, Inp_RC_ManualLots, "遥控") ? "已强制开空" : "开空失败"; break;
         case RC_CMD_CLOSE_BUY:  r = StringFormat("已平多单 %d 张", GH_CloseSide(0));  break;
         case RC_CMD_CLOSE_SELL: r = StringFormat("已平空单 %d 张", GH_CloseSide(1));  break;
         case RC_CMD_CLOSE_ALL:  r = StringFormat("已全部平仓 %d 张", GH_CloseSide(-1)); break;
         case RC_CMD_TP_TO_BE:
           {
            int n = GH_BreakEven();
            if(GH_HasSide(0)) RC_SetBE(0, true);
            if(GH_HasSide(1)) RC_SetBE(1, true);
            r = StringFormat("保本已设置 %d 张", n);
            break;
           }
         default: r = "未处理的动作 " + IntegerToString(a); break;
        }
      RC_Done(r);
      g_uiLastAct = "遥控: " + r;
      if(g_uiLive) UiLog(g_uiLastAct);
     }
   if(RC_IsBE(0) && !GH_HasSide(0)) RC_ClearBE(0);
   if(RC_IsBE(1) && !GH_HasSide(1)) RC_ClearBE(1);
  }

//--- 全视界面板初始化(非可视回测直接跳过: 不建对象、不渲染)
void GH_UiInit()
  {
   bool tester = (MQLInfoInteger(MQL_TESTER) != 0 || MQLInfoInteger(MQL_OPTIMIZATION) != 0);
   bool visual = (MQLInfoInteger(MQL_VISUAL_MODE) != 0);
   g_uiLive = !(tester && !visual);
   if(!g_uiLive) return;
   UiInit("GHX", Inp_BaseMagic);
   CPanelEngine *pn = UiPanel();
   if(pn != NULL)
     {
      pn.SetMagicRange(Inp_BaseMagic + 1, Inp_BaseMagic + GH_NSTRAT);
      pn.SetTitle("★ 全视界量化引擎 · 黄金城 " + GH_VERSION + " · ");
     }
   UiAltEnable(true);
   UiAltTitle("═══ 黄金城 " + GH_VERSION + " · 五策略结构位突破 · 行为学复刻 ═══");
   UiAltSection(0, "▌结构位布防 · 上下边界");
   UiAltSection(1, "▌挂单引擎 · 亏损冷却");
   UiAltSection(2, "▌交易许可 · 阻断证据");
   UiAltSection(3, "▌追踪止损引擎 · 双锚取紧");
   UiAltSection(4, "▌点差与品种");
   UiAltSection(5, "▌持仓明细");
   UiAltSection(6, "▌指令挂单遥控");
   UiAltSection(7, "▌风控执行状态");
   UiAltSection(8, "═══════════ 系统日志 ═══════════");
   UiLog(StringFormat("黄金城 %s 启动 | %s", GH_VERSION, SA_Describe()));
   GH_UiRender();
  }

//--- 面板按钮(测试器不派发 OnChartEvent, 统一轮询)
void GH_UiButtons()
  {
   CPanelEngine *pn = UiPanel();
   if(pn == NULL) return;
   string P = pn.Prefix();
   if(pn.ConsumePress(P + "_RBB")) GH_ManualOpen(true,  pn.GetManualLots(Inp_RC_ManualLots), "面板");
   if(pn.ConsumePress(P + "_RBS")) GH_ManualOpen(false, pn.GetManualLots(Inp_RC_ManualLots), "面板");
   if(pn.ConsumePress(P + "_RBC")) { g_uiLastAct = StringFormat("面板全部平仓 %d 张", GH_CloseSide(-1)); UiLog(g_uiLastAct); }
   if(pn.ConsumePress(P + "_RCB")) { g_uiLastAct = StringFormat("面板平多 %d 张", GH_CloseSide(0));  UiLog(g_uiLastAct); }
   if(pn.ConsumePress(P + "_RCS")) { g_uiLastAct = StringFormat("面板平空 %d 张", GH_CloseSide(1));  UiLog(g_uiLastAct); }
   if(pn.ConsumePress(P + "_RCP"))
     {
      int n = MyPendings();
      PurgeMyPendings();
      g_uiLastAct = StringFormat("面板撤销挂单 %d 张%s", n, (g_uiPaused ? "" : "(未暂停: 策略将按结构位重新布防)"));
      UiLog(g_uiLastAct);
     }
   if(pn.ConsumePress(P + "_RBA"))
     {
      string why = GH_BlockReason();
      UiLog(StringFormat("自检: 许可=%s | 持仓 %d | 挂单 %d | 熔断=%s | U=%.3f",
                         (why == "" ? "放行" : why), MyPositions(), MyPendings(), (g_halted ? "是" : "否"), Unit()));
      for(int i = 0; i < GH_NSTRAT; i++)
         if(S[i].on)
            UiLog(StringFormat("  %s 结构位 上%s 下%s | 挂单背后 买%s 卖%s", S[i].tag,
                               GH_Px(S[i].ceilv), GH_Px(S[i].floorv), GH_Px(S[i].armB), GH_Px(S[i].armS)));
     }
   if(pn.ConsumePress(P + "_RRST"))
     {
      pn.ResetStartTime(); pn.ClearLog();
      g_uiMaxDD = 0; g_uiMaxDDT = 0; g_uiLastAct = "";
      UiLog("运行统计与面板日志已归零");
     }
   if(pn.ConsumePress(P + "_RPSE"))
     {
      g_uiPaused = !g_uiPaused;
      g_uiLastAct = (g_uiPaused ? "面板暂停: 停止新挂单(持仓照常追踪)" : "面板恢复: 继续布防");
      UiLog(g_uiLastAct);
     }
  }

//--- 分策略已平统计(5 秒刷新一次, 只读历史)
void GH_StratStats()
  {
   if(TimeCurrent() - g_uiStatT < 5 && g_uiStatT > 0) return;
   g_uiStatT = TimeCurrent();
   for(int i = 0; i < GH_NSTRAT; i++) { g_stN[i] = 0; g_stW[i] = 0; g_stP[i] = 0; }
   if(!HistorySelect(0, TimeCurrent() + 86400)) return;
   int n = HistoryDealsTotal();
   for(int k = 0; k < n; k++)
     {
      ulong dl = HistoryDealGetTicket(k);
      if(dl == 0) continue;
      if(HistoryDealGetString(dl, DEAL_SYMBOL) != _Symbol) continue;
      int si = StratIndexByMagic(HistoryDealGetInteger(dl, DEAL_MAGIC));
      if(si < 0) continue;
      ENUM_DEAL_ENTRY en = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dl, DEAL_ENTRY);
      if(en != DEAL_ENTRY_OUT && en != DEAL_ENTRY_OUT_BY && en != DEAL_ENTRY_INOUT) continue;
      double p = HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP)
               + HistoryDealGetDouble(dl, DEAL_COMMISSION);
      g_stN[si]++; g_stP[si] += p; if(p > 0) g_stW[si]++;
     }
  }

//--- 全视界面板喂数 + 渲染(每秒一次; 仅 g_uiLive 时调用)
void GH_UiRender()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double U   = Unit();
   double pip = SA_Pip(); if(pip <= 0) pip = g_pip;
   datetime now = TimeCurrent();

   //---- 持仓与挂单盘点
   int    nb = 0, ns = 0, np = 0;
   double lot = 0, wavg = 0, fpl = 0;
   string rows[];  color rclr[];  int rn = 0;
   ArrayResize(rows, 64); ArrayResize(rclr, 64);
   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong tk = PositionGetTicket(p);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      long mg = PositionGetInteger(POSITION_MAGIC);
      if(!GH_IsEAPos(mg)) continue;
      bool   buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double v   = PositionGetDouble(POSITION_VOLUME);
      double op  = PositionGetDouble(POSITION_PRICE_OPEN);
      double pr  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(buy) nb++; else ns++;
      lot += v; wavg += v * op; fpl += pr;
      int si = StratIndexByMagic(mg);
      if(rn < 64)
        {
         rows[rn] = StringFormat("%s %s仓 #%I64u %.2f手 开%s 损%s 盈%s 浮%s",
                                 (si >= 0 ? S[si].tag : "人工"), (buy ? "多" : "空"), tk, v,
                                 GH_Px(op), GH_Px(PositionGetDouble(POSITION_SL)), GH_Px(PositionGetDouble(POSITION_TP)), GH_Sgn(pr));
         rclr[rn] = (pr >= 0 ? C'120,230,160' : C'255,140,120');
         rn++;
        }
     }
   for(int o = OrdersTotal() - 1; o >= 0; o--)
     {
      ulong tk = OrderGetTicket(o);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      long mg = OrderGetInteger(ORDER_MAGIC);
      int si = StratIndexByMagic(mg);
      if(si < 0) continue;
      np++;
      ENUM_ORDER_TYPE ty = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      bool   buy = (ty == ORDER_TYPE_BUY_STOP);
      double op  = OrderGetDouble(ORDER_PRICE_OPEN);
      datetime ex = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      if(ex <= 0 && S[si].expH > 0) ex = (datetime)OrderGetInteger(ORDER_TIME_SETUP) + S[si].expH * 3600;
      if(rn < 64)
        {
         rows[rn] = StringFormat("%s %s挂 #%I64u 价%s 损%s 盈%s 距%.1fpip 剩%s",
                                 S[si].tag, (buy ? "买" : "卖"), tk, GH_Px(op),
                                 GH_Px(OrderGetDouble(ORDER_SL)), GH_Px(OrderGetDouble(ORDER_TP)),
                                 MathAbs(op - (buy ? ask : bid)) / pip, (ex > 0 ? GH_Clock((long)(ex - now)) : "GTC"));
         rclr[rn] = (buy ? C'120,190,255' : C'230,150,230');
         rn++;
        }
     }
   if(-fpl > g_uiMaxDD) { g_uiMaxDD = -fpl; g_uiMaxDDT = now; }
   CollectBoundary();
   GH_StratStats();

   //---- 基础喂数(版式所需; 黄金城无整篮止盈/止损线, 无虚拟接管)
   g_fd.verTag     = GH_VERSION;
   g_fd.tfMin      = PeriodSeconds() / 60;
   g_fd.magic      = Inp_BaseMagic;
   g_fd.pt         = _Point;
   g_fd.rBuy = nb; g_fd.rSell = ns; g_fd.rCnt = nb + ns;
   g_fd.rTotLot = lot; g_fd.rAvg = (lot > 0 ? wavg / lot : 0); g_fd.rPL = fpl;
   g_fd.rType  = (nb > 0 && ns == 0) ? UI_OP_BUY : ((ns > 0 && nb == 0) ? UI_OP_SELL : -1);
   g_fd.rMixed = false;                           // 双向同时持仓是本策略常态, 不作告警
   g_fd.mixed  = false;
   g_fd.maxDD  = g_uiMaxDD; g_fd.maxDDTime = g_uiMaxDDT;
   g_fd.redLine = 0; g_fd.blackLine = 0; g_fd.tpArmed = true; g_fd.slArmed = true;
   g_fd.serverOn = true; g_fd.tpUSD = 0; g_fd.slUSD = 0; g_fd.basketMargin = AccountInfoDouble(ACCOUNT_MARGIN);
   g_fd.cnt = nb + ns; g_fd.buyCnt = nb; g_fd.sellCnt = ns; g_fd.type = g_fd.rType;
   g_fd.totLot = lot; g_fd.avg = g_fd.rAvg; g_fd.pl = fpl; g_fd.maxLayers = GH_NSTRAT * 2;
   g_fd.nextLot = Inp_FixedLots; g_fd.nextAddPx = 0; g_fd.gapPts = 0; g_fd.throttleSec = 0;
   g_fd.vomOn = false;
   g_fd.paused = (g_uiPaused || RC_BlockNew()); g_fd.halted = g_halted; g_fd.closing = false;
   g_fd.lastAction = g_uiLastAct;
   string why = GH_BlockReason();
   g_fd.sigSrc = g_halted ? "HALT" : (g_fd.paused ? "PAUSE" : "LIVE");

   //---- 左栏覆写(黄金城真实机制)
   UiOverrideClear();
   color cOK = C'120,220,160', cWarn = clrGold, cBad = clrTomato, cTxt = C'160,170,180';
   double ddNow = (g_peakEquity > 0) ? (g_peakEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / g_peakEquity * 100.0 : 0;
   UiOverride("_GS", StringFormat("回撤熔断: 峰值回撤 %.2f%% / 阈值 %s | 单日阈值 %s | 状态 %s", ddNow,
              (Inp_MaxDrawdownPct > 0 ? DoubleToString(Inp_MaxDrawdownPct, 1) + "%" : "关"),
              (Inp_DailyDDPct > 0 ? DoubleToString(Inp_DailyDDPct, 1) + "%" : "关"),
              (g_halted ? "已熔断" : "正常")), (g_halted ? cBad : clrOrange));
   UiOverride("_TRAIL", StringFormat("追踪×U: A%.2f B%.2f C%.2f D%.2f E%.2f | 启动 A%.1f | U = %.3f%%×Ask = %.3f",
              S[0].trU, S[1].trU, S[2].trU, S[3].trU, S[4].trU, S[0].trStart, Inp_UnitPct * 100, U), clrGold);
   UiOverride("_RECY", StringFormat("布防: 买缓冲 %.6fU / 卖缓冲 %.6fU | 有效期 A%dh B%dh C%dh D%dh E%dh",
              Inp_BuyOffsetU, Inp_SellOffsetU, S[0].expH, S[1].expH, S[2].expH, S[3].expH, S[4].expH), clrAqua);
   UiOverride("_ML", StringFormat("本EA持仓: 多%d 空%d | 挂单 %d 张 | 浮动 %s | 预付款 %.2f",
              nb, ns, np, GH_Sgn(fpl), AccountInfoDouble(ACCOUNT_MARGIN)), (fpl >= 0 ? clrCyan : cBad));
   UiOverride("_RC", StringFormat("服务器保护: 每单独立 SL/TP 托管 | 亏损冷却 %d 分钟(盈利平仓 0 秒补挂)", Inp_SLCooldownMin),
              C'200,160,255');
   UiOverride("_SCAN", "最近动作: " + (g_uiLastAct == "" ? "—" : g_uiLastAct), (g_fd.paused ? cWarn : C'200,200,140'));
   UiOverride("_CD", StringFormat("◆ 周末保护%s: 周五%d点停挂/%d点删挂/%d点平仓 · 周一%d点前暂停 | 遥控 %s",
              (Inp_WeekendClose ? "开" : "关"), g_fridayNoEntry, Inp_FridayDelPend, Inp_FridayClosePos, Inp_MondayResume,
              RC_StatusText()), C'180,200,220');
   UiOverride("_FSN_1", StringFormat("▲CEILING %s (距 %.1f pip, %d 张)  ▼FLOOR %s (距 %.1f pip, %d 张)",
              GH_Px(g_uiCeil),  (g_uiCeil  > 0 ? (g_uiCeil - ask) / pip : 0), g_uiCeilOrd,
              GH_Px(g_uiFloor), (g_uiFloor > 0 ? (bid - g_uiFloor) / pip : 0), g_uiFloorOrd), C'170,200,230');
   UiOverride("_FSN_2", StringFormat("[%s] 启用 A%s B%s C%s D%s E%s | 结构位: 事件驱动状态机 + 未击穿自举",
              g_fd.sigSrc, (S[0].on ? "●" : "○"), (S[1].on ? "●" : "○"), (S[2].on ? "●" : "○"),
              (S[3].on ? "●" : "○"), (S[4].on ? "●" : "○")),
              (g_halted ? cBad : (g_fd.paused ? cWarn : C'150,200,170')));
   string cool = "";
   for(int i = 0; i < GH_NSTRAT; i++)
      for(int d = 0; d < 2; d++)
         if(g_coolTo[i][d] > now)
            cool += StringFormat("%s%s 剩%s  ", S[i].tag, (d == 0 ? "买" : "卖"), GH_Clock((long)(g_coolTo[i][d] - now)));
   UiOverride("_T1_1", (cool == "" ? "冷却槽: 无(全部可布防)" : "冷却槽: " + cool), (cool == "" ? C'160,190,220' : cWarn));
   UiOverride("_T2_1", (why == "" ? "交易许可: 放行 · 五策略布防中" : "交易许可: 阻断 —— " + why), (why == "" ? C'120,180,255' : cWarn));
   UiOverride("_T2_2", StringFormat("点差闸 %.0f/%.0f 点 | 新闻过滤 %s | 保守模式 %s",
              SpreadPoints(), Inp_MaxSpreadPts, (Inp_UseNewsFilter ? (g_newsBlock ? "封锁中" : "开") : "关"),
              (Inp_ConservativeMode ? "开" : "关")), C'100,160,235');
   UiOverride("_T3_1", "锚1 入场重锚 = 开仓价 ∓ (止损×U + 实时点差) | 锚2 新极值追踪 = 买 maxBid−t×U / 卖 minAsk+t×U", C'160,190,220');
   UiOverride("_T3_2", StringFormat("两锚取更紧者、只收紧不放松 | 登记持仓 %d 个 | 止损×U A%.1f B%.1f C%.1f D%.1f E%.1f",
              g_ntrk, S[0].slU, S[1].slU, S[2].slU, S[3].slU, S[4].slU), cTxt);
   UiOverride("_BULL_1", StringFormat("点差 %.1f pip (%.0f 点) | Bid %s  Ask %s", (ask - bid) / pip, SpreadPoints(),
              DoubleToString(bid, g_digits), DoubleToString(ask, g_digits)), cTxt);
   UiOverride("_BULL_2", SA_Describe(), cTxt);
   UiOverride("_BEAR_1", (rn > 0 ? rows[0] : "无持仓 / 无挂单"), (rn > 0 ? rclr[0] : cTxt));
   UiOverride("_BEAR_2", (rn > 1 ? rows[1] + (rn > 2 ? StringFormat("  … 另 %d 行见右栏", rn - 2) : "") : ""), (rn > 1 ? rclr[1] : cTxt));
   UiOverride("_TRD_1", "遥控: " + RC_StatusText(), (Inp_RC_Enable ? C'150,190,240' : C'140,150,160'));
   UiOverride("_TRD_2", (Inp_RC_Enable ? "码位: " + RC_CodeMap() + " | 最近: " + RC_LastAction()
                                       : "参数【启用手机遥控】打开后: 手机改哨兵单止盈 = 下指令"), C'170,180,190');
   UiOverride("_FINAL_1", (g_halted ? "风控: 已熔断 —— 停止布防" : (why == "" ? "风控: 正常运行" : "风控: 暂停布防 —— " + why)),
              (g_halted ? cBad : (why == "" ? clrLime : cWarn)));
   UiOverride("_FINAL_2", StringFormat("峰值净值 %.2f | 日初净值 %.2f | 回撤口径 %s | 动作 %s",
              g_peakEquity, g_dayStartEq, (Inp_DDAccountWide ? "账户净值" : "仅本EA"), (Inp_CloseAll ? "平账户全部" : "仅平本EA")),
              C'190,190,190');

   //---- 右栏镜像区 13 行: 五策略状态 + 分策略已平统计
   UiAltMirror(0, "★ 五策略布防看板 · 黄金城 " + GH_VERSION, clrGold);
   UiAltMirror(1, StringFormat("结构时间框: A/D/E=%s C=%s B=%s | U=%.3f", EnumToString(S[0].tf), EnumToString(S[2].tf),
               EnumToString(S[1].tf), U), C'160,170,180');
   int    sN = 0, sW = 0; double sP = 0;
   for(int i = 0; i < GH_NSTRAT; i++)
     {
      bool hb = HoldingDir(i, POSITION_TYPE_BUY), hs = HoldingDir(i, POSITION_TYPE_SELL);
      string st = StringFormat("%s %s 枢轴 买%d/%d 卖%d/%d | 上%s 下%s | %s%s%s", S[i].tag, (S[i].on ? "●" : "○"),
                               S[i].leftB, S[i].fracB, S[i].leftS, S[i].frac,
                               GH_Px(S[i].ceilv), GH_Px(S[i].floorv),
                               (hb ? "多仓 " : ""), (hs ? "空仓 " : ""),
                               ((g_coolTo[i][0] > now || g_coolTo[i][1] > now) ? "冷却中" : ""));
      UiAltMirror(2 + i, st, (S[i].on ? C'150,210,240' : C'120,130,140'));
      double wr = (g_stN[i] > 0 ? g_stW[i] * 100.0 / g_stN[i] : 0);
      UiAltMirror(7 + i, StringFormat("%s 已平 %d 笔 | 胜率 %.1f%% | 净利 %s", S[i].tag, g_stN[i], wr, GH_Sgn(g_stP[i])),
                  (g_stP[i] >= 0 ? C'120,220,160' : C'255,140,120'));
      sN += g_stN[i]; sW += g_stW[i]; sP += g_stP[i];
     }
   UiAltMirror(12, StringFormat("合计 已平 %d 笔 | 胜率 %.1f%% | 净利 %s", sN, (sN > 0 ? sW * 100.0 / sN : 0), GH_Sgn(sP)),
               (sP >= 0 ? clrLime : clrTomato));

   //---- 右栏对账台: 汇总 8 行 + 明细
   UiAltBoardHead(StringFormat("▌五策略 · 挂单与持仓明细 (持仓 %d / 挂单 %d)", nb + ns, np));
   UiAltSum(0, StringFormat("余额 %.2f | 净值 %.2f | 浮动 %s", AccountInfoDouble(ACCOUNT_BALANCE),
            AccountInfoDouble(ACCOUNT_EQUITY), GH_Sgn(fpl)), C'200,200,130');
   UiAltSum(1, StringFormat("浮亏峰值 -%.2f @%s", g_uiMaxDD, (g_uiMaxDDT > 0 ? TimeToString(g_uiMaxDDT, TIME_DATE | TIME_MINUTES) : "尚未发生")),
            (g_uiMaxDD > 0 ? cBad : cTxt));
   UiAltSum(2, StringFormat("占槽铁律: 同策略同方向「挂单+持仓」互斥 | 魔术号 %d~%d", Inp_BaseMagic + 1, Inp_BaseMagic + GH_NSTRAT), C'170,205,215');
   UiAltSum(3, StringFormat("止损×U A%.1f B%.1f C%.1f D%.1f E%.1f", S[0].slU, S[1].slU, S[2].slU, S[3].slU, S[4].slU), C'230,170,170');
   UiAltSum(4, StringFormat("止盈×U A%.1f B%.1f C%.1f D%.1f E%.1f", S[0].tpU, S[1].tpU, S[2].tpU, S[3].tpU, S[4].tpU), C'170,230,170');
   UiAltSum(5, StringFormat("手数模式 %s | 固定 %.2f 手 | 人工单魔术号 %I64d", EnumToString(Inp_LotMode), Inp_FixedLots, Inp_RC_ManualMagic), clrLime);
   UiAltSum(6, (why == "" ? "布防许可: 放行" : "布防许可: " + why), (why == "" ? C'170,200,190' : cWarn));
   UiAltSum(7, "OnTester = 盈利因子 × 采收率 × 夏普 × √交易数 (与原版同口径)", C'160,170,180');
   UiAltColHead("策略 类型 单号 手数/价格 止损 止盈 距离/浮动");
   UiAltRows(rn);
   for(int k = 0; k < rn; k++) UiAltRow(k, rows[k], rclr[k]);

   UiRender();
  }
//+------------------------------------------------------------------+
