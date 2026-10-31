//+------------------------------------------------------------------+
//|                                   指令挂单遥控模块_MT5_v1.1.mqh   |
//|  手机改挂单止盈 = 给 EA 下指令（MQL5 原生移植，可被任何 MT5 EA 复用）|
//+------------------------------------------------------------------+
//  v1.1（MT5 原生移植）
//   · v1.0 内部是 MQL4 交易 API（OrderSelect(i,SELECT_BY_POS)/OrderSend/OrderModify/MarketInfo/
//     IsTradeContextBusy/OP_BUYLIMIT），MQL5 无法编译。本版全部改为 MQL5 原生：
//     OrdersTotal+OrderGetTicket 枚举、MqlTradeRequest(TRADE_ACTION_PENDING / TRADE_ACTION_MODIFY)。
//   · 单号改为 ulong（MT5 单号可超出 int 范围）。
//   · 对外接口（RC_Setup/RC_SetCode/RC_LoadState/RC_Poll/RC_Done/RC_BlockNew/RC_BlockAdd/
//     RC_IsBE/RC_SetBE/RC_ClearBE/RC_StatusText/RC_LastAction/RC_Ticket/RC_Magic）与 v1.0 同名同义。
//  原理：EA 挂一张永不成交的买入限价单（哨兵单，价位远低于现价）。在手机 MT5 上把它的「止盈」
//        改成指令码（例如 777），EA 每秒轮询读到后执行对应动作，再把止盈写回待机码（例如 666）作回执。
//  设计要点：
//   · 哨兵单使用宿主传入的「独立魔术号」：宿主按自己的魔术号统计订单 → 哨兵单绝不进入宿主交易逻辑
//   · 幂等：同一个止盈值只执行一次；回执写回失败只重试写回，绝不重复执行指令
//   · 哨兵价 ≥ 100 时自动改读相对码（止盈 − 挂单价），避免止盈栏放不下指令码
//   · 回测中默认完全不启用（不挂单、不轮询、不读写全局变量）→ 回测报告与未接入时逐笔一致
//   · 停开新篮 / 停一切开仓 / 保本 可写入终端全局变量，重启后自动恢复（回测中不读不写）
//  约定：本模块只读写「自己的哨兵单」，不碰宿主任何订单。
//+------------------------------------------------------------------+
#ifndef RC_MODULE_V11
#define RC_MODULE_V11

enum ENUM_RC_CMD
  {
   RC_CMD_NONE       = 0,   // 0 无动作（心跳测试，只回执）
   RC_CMD_OPEN_BUY   = 1,   // 1 强制开多
   RC_CMD_OPEN_SELL  = 2,   // 2 强制开空
   RC_CMD_CLOSE_BUY  = 3,   // 3 平掉全部多单
   RC_CMD_CLOSE_SELL = 4,   // 4 平掉全部空单
   RC_CMD_CLOSE_ALL  = 5,   // 5 全部平仓
   RC_CMD_TP_TO_BE   = 6,   // 6 移到保本
   RC_CMD_PAUSE_NEW  = 7,   // 7 停开新单（已有持仓照常管理）
   RC_CMD_STOP_ALL   = 8,   // 8 停止一切开仓（平仓照常）
   RC_CMD_RESUME     = 9    // 9 恢复全部（解除停开/保本）
  };

#define RC_SLOTS 6

//--- 配置（RC_Setup 写入）
bool   RC_cfgOn        = false;
bool   RC_cfgTester    = false;      // 仅供模块自测：true 时允许在策略测试器内运行（生产 EA 一律传 false）
long   RC_cfgMagic     = 0;
double RC_cfgPrice     = 3.0;
double RC_cfgLots      = 0.01;
double RC_cfgStandby   = 666.0;
bool   RC_cfgWriteBack = true;
bool   RC_cfgAutoPlace = true;
bool   RC_cfgPersist   = true;
int    RC_cfgSlip      = 30;
string RC_cfgTag       = "[遥控] ";
string RC_cfgGV        = "RC_";
string RC_cfgComment   = "CMD";
double RC_code[RC_SLOTS];
int    RC_act[RC_SLOTS];

//--- 运行期
ulong    RC_ticket     = 0;          // 当前哨兵单单号（0=不存在）
double   RC_codeNow    = 0.0;        // 当前读到的码值
double   RC_doneTP     = 0.0;        // 幂等锁：已执行过的止盈值（看到待机码才解锁）
uint     RC_pollMs     = 0;
datetime RC_placeAt    = 0;
string   RC_state      = "未启用";
string   RC_lastAct    = "—";
bool     RC_noNew      = false;      // 停开新单
bool     RC_noAdd      = false;      // 停止一切开仓
bool     RC_be[2];                   // 保本：0=多 1=空
bool     RC_pending    = false;      // 已交给宿主、等待 RC_Done 回执的指令
ulong    RC_pendTicket = 0;
double   RC_pendBase   = 0.0;
double   RC_pendCode   = 0.0;
uint     RC_lastRet    = 0;          // 最近一次交易请求返回码

//+------------------------------------------------------------------+
string RC_ActName(const int act)
  {
   switch(act)
     {
      case RC_CMD_NONE:       return("心跳");
      case RC_CMD_OPEN_BUY:   return("强制开多");
      case RC_CMD_OPEN_SELL:  return("强制开空");
      case RC_CMD_CLOSE_BUY:  return("平掉全部多单");
      case RC_CMD_CLOSE_SELL: return("平掉全部空单");
      case RC_CMD_CLOSE_ALL:  return("全部平仓");
      case RC_CMD_TP_TO_BE:   return("移到保本");
      case RC_CMD_PAUSE_NEW:  return("停开新单");
      case RC_CMD_STOP_ALL:   return("停止一切开仓");
      case RC_CMD_RESUME:     return("恢复全部");
     }
   return("未知动作" + IntegerToString(act));
  }

bool RC_InTester()               { return(MQLInfoInteger(MQL_TESTER) != 0 || MQLInfoInteger(MQL_OPTIMIZATION) != 0); }
bool RC_Active()                 { return(RC_cfgOn && (!RC_InTester() || RC_cfgTester)); }
bool RC_GVOk()                   { return(RC_cfgPersist && RC_Active() && !RC_InTester()); }
string RC_GVName(const string k) { return(RC_cfgGV + k); }

void RC_GVSet(const string k, const bool v)
  {
   if(!RC_GVOk()) return;
   GlobalVariableSet(RC_GVName(k), v ? 1.0 : 0.0);
  }

bool RC_GVGet(const string k)
  {
   if(!RC_GVOk()) return(false);
   if(!GlobalVariableCheck(RC_GVName(k))) return(false);
   return(GlobalVariableGet(RC_GVName(k)) > 0.5);
  }

void RC_Save()
  {
   RC_GVSet("STOPNEW", RC_noNew);
   RC_GVSet("STOPADD", RC_noAdd);
   RC_GVSet("BE_BUY",  RC_be[0]);
   RC_GVSet("BE_SELL", RC_be[1]);
  }

//--- 初始化配置。gvPrefix 用于全局变量名（建议含魔术号+品种），comment 为哨兵单注释（建议纯 ASCII）
void RC_Setup(const bool on, const long magic, const double price, const double lots, const double standby,
              const bool writeBack, const bool autoPlace, const bool persist, const int slippagePts,
              const string logTag, const string gvPrefix, const string comment, const bool allowInTester)
  {
   RC_cfgOn        = on;
   RC_cfgMagic     = magic;
   RC_cfgPrice     = price;
   RC_cfgLots      = lots;
   RC_cfgStandby   = standby;
   RC_cfgWriteBack = writeBack;
   RC_cfgAutoPlace = autoPlace;
   RC_cfgPersist   = persist;
   RC_cfgSlip      = slippagePts;
   RC_cfgTag       = logTag;
   RC_cfgGV        = gvPrefix;
   RC_cfgComment   = comment;
   RC_cfgTester    = allowInTester;
   for(int i = 0; i < RC_SLOTS; i++) { RC_code[i] = -1.0; RC_act[i] = RC_CMD_NONE; }
   RC_ticket = 0;  RC_codeNow = 0.0;  RC_doneTP = 0.0;  RC_pollMs = 0;  RC_placeAt = 0;
   RC_noNew = false;  RC_noAdd = false;  RC_be[0] = false;  RC_be[1] = false;
   RC_pending = false;  RC_pendTicket = 0;  RC_pendBase = 0.0;  RC_pendCode = 0.0;
   RC_lastAct = "—";
   if(!RC_cfgOn)          RC_state = "未启用";
   else if(!RC_Active())  RC_state = "回测中不启用";
   else                   RC_state = "启动中";
  }

//--- 码位 1..6
void RC_SetCode(const int slot, const double code, const int act)
  {
   if(slot < 1 || slot > RC_SLOTS) return;
   RC_code[slot - 1] = code;
   RC_act[slot - 1]  = act;
  }

//--- 重启恢复遥控状态（仅实盘且启用持久化）
void RC_LoadState()
  {
   if(!RC_GVOk()) return;
   RC_noNew = RC_GVGet("STOPNEW");
   RC_noAdd = RC_GVGet("STOPADD");
   RC_be[0] = RC_GVGet("BE_BUY");
   RC_be[1] = RC_GVGet("BE_SELL");
   if(RC_noNew || RC_noAdd || RC_be[0] || RC_be[1])
      Print(RC_cfgTag + "已恢复上次运行的遥控状态：" + (RC_noAdd ? "停止一切开仓 " : (RC_noNew ? "停开新单 " : "")) +
            ((RC_be[0] || RC_be[1]) ? "保本 " : "") + "—— 发恢复码即可解除");
  }

//--- 码位一览（日志用）
string RC_CodeMap()
  {
   string s = "";
   for(int i = 0; i < RC_SLOTS; i++)
     {
      if(RC_code[i] <= 0.0) continue;
      if(StringLen(s) > 0) s += "  ";
      s += DoubleToString(RC_code[i], 0) + "=" + RC_ActName(RC_act[i]);
     }
   return(s);
  }

//--- 哨兵手数规整
double RC_NormLots(double v)
  {
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(st <= 0.0) st = 0.01;
   v = MathRound(v / st) * st;
   if(mn > 0.0 && v < mn) v = mn;
   if(mx > 0.0 && v > mx) v = mx;
   return(NormalizeDouble(v, 8));
  }

bool   RC_Relative(const double base)                   { return(base >= 100.0); }
double RC_Encode(const double code, const double base)  { return(NormalizeDouble(RC_Relative(base) ? base + code : code, _Digits)); }

//--- 挂单成交方式(挂单一律 RETURN 兼容性最好;券商只允许 FOK/IOC 时按其所允许)
ENUM_ORDER_TYPE_FILLING RC_Filling()
  {
   long fm = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   ENUM_SYMBOL_TRADE_EXECUTION ex = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   if(ex == SYMBOL_TRADE_EXECUTION_MARKET || ex == SYMBOL_TRADE_EXECUTION_EXCHANGE) return(ORDER_FILLING_RETURN);
   if((fm & SYMBOL_FILLING_FOK) != 0) return(ORDER_FILLING_FOK);
   if((fm & SYMBOL_FILLING_IOC) != 0) return(ORDER_FILLING_IOC);
   return(ORDER_FILLING_RETURN);
  }

//--- 查找本模块的哨兵单（本品种 + 独立魔术号 + 买入限价 + 哨兵手数；多张时取最接近设定价位的一张）
ulong RC_Find()
  {
   ulong  best  = 0;
   double bestD = DBL_MAX;
   double lots  = RC_NormLots(RC_cfgLots);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != RC_cfgMagic) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_LIMIT) continue;
      if(MathAbs(OrderGetDouble(ORDER_VOLUME_CURRENT) - lots) >= 0.0001) continue;
      double d = MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - RC_cfgPrice);
      if(d < bestD) { bestD = d; best = tk; }
     }
   return(best);
  }

//--- 挂出哨兵单：设定价位 → 现价×10% → 现价×50%，依次尝试
bool RC_Create()
  {
   if(RC_Find() != 0) return(true);
   double lots = RC_NormLots(RC_cfgLots);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minD = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double cand[3];
   cand[0] = RC_cfgPrice;
   cand[1] = ask * 0.10;
   cand[2] = ask * 0.50;
   for(int i = 0; i < 3; i++)
     {
      double px = NormalizeDouble(cand[i], _Digits);
      if(px <= 0.0 || px >= ask - minD) continue;                           // 买入限价必须低于现价（含 StopLevel）
      if(i > 0 && MathAbs(px - NormalizeDouble(cand[0], _Digits)) < _Point) continue;
      double tp = RC_Encode(RC_cfgStandby, px);
      if(tp <= px + minD) continue;                                         // 买入限价的止盈必须高于挂单价
      MqlTradeRequest rq; MqlTradeResult rs;
      ZeroMemory(rq); ZeroMemory(rs);
      rq.action       = TRADE_ACTION_PENDING;
      rq.symbol       = _Symbol;
      rq.volume       = lots;
      rq.type         = ORDER_TYPE_BUY_LIMIT;
      rq.price        = px;
      rq.sl           = 0.0;
      rq.tp           = tp;
      rq.deviation    = (ulong)RC_cfgSlip;
      rq.magic        = (ulong)RC_cfgMagic;
      rq.comment      = RC_cfgComment;
      rq.type_time    = ORDER_TIME_GTC;
      rq.type_filling = RC_Filling();
      ResetLastError();
      bool ok = OrderSend(rq, rs);
      RC_lastRet = rs.retcode;
      if(ok && (rs.retcode == TRADE_RETCODE_DONE || rs.retcode == TRADE_RETCODE_PLACED) && rs.order > 0)
        {
         Print(RC_cfgTag + "指令单已挂出 #" + IntegerToString((long)rs.order) + " @" + DoubleToString(px, _Digits) +
               "  待机码 " + DoubleToString(RC_cfgStandby, 0) + "  魔术号 " + IntegerToString(RC_cfgMagic) +
               "  读码方式 " + (RC_Relative(px) ? "相对（止盈−挂单价）" : "绝对（直接读止盈）"));
         if(RC_Relative(px))
            Print(RC_cfgTag + "【注意】低价哨兵被拒，已改用相对读码：手机上要填的止盈 = 挂单价 + 指令码，例如 777 → 止盈填 " +
                  DoubleToString(px + 777.0, _Digits));
         return(true);
        }
      Print(RC_cfgTag + "哨兵价 " + DoubleToString(px, _Digits) + " 被拒 rc=" + IntegerToString((int)rs.retcode) +
            " err=" + IntegerToString(GetLastError()) + " → 尝试下一个");
     }
   Print(RC_cfgTag + "全部哨兵价均被券商拒绝，遥控通道暂不可用（60 秒后自动重试；可调整「遥控哨兵单挂单价位」）");
   return(false);
  }

//--- 把止盈写回待机码（回执）
bool RC_WriteStandby(const ulong tk, const double base)
  {
   double tp = RC_Encode(RC_cfgStandby, base);
   for(int r = 0; r < 3; r++)
     {
      if(!OrderSelect(tk)) return(false);                                   // 哨兵单已不存在
      if(MathAbs(OrderGetDouble(ORDER_TP) - tp) < _Point * 0.5) return(true); // 已是待机码
      MqlTradeRequest rq; MqlTradeResult rs;
      ZeroMemory(rq); ZeroMemory(rs);
      rq.action     = TRADE_ACTION_MODIFY;
      rq.order      = tk;
      rq.symbol     = _Symbol;
      rq.price      = base;
      rq.sl         = 0.0;
      rq.tp         = tp;
      rq.type_time  = ORDER_TIME_GTC;
      rq.expiration = 0;
      ResetLastError();
      bool ok = OrderSend(rq, rs);
      RC_lastRet = rs.retcode;
      if(ok && (rs.retcode == TRADE_RETCODE_DONE || rs.retcode == TRADE_RETCODE_PLACED)) return(true);
      if(rs.retcode == TRADE_RETCODE_NO_CHANGES) return(true);
      if(!RC_InTester()) Sleep(80);
     }
   return(false);
  }

void RC_Finish(const ulong tk, const double base)
  {
   if(!RC_cfgWriteBack) return;                                             // 不写回：用户需手动改回待机码（幂等锁保持）
   if(RC_WriteStandby(tk, base)) RC_doneTP = 0.0;
   else Print(RC_cfgTag + "写回待机码失败 rc=" + IntegerToString((int)RC_lastRet) + " —— 下一秒重试写回（幂等保护：该指令不会重复执行）");
  }

//+------------------------------------------------------------------+
//| 轮询：返回需要宿主执行的动作（RC_CMD_*），无事返回 -1；每秒最多一次 |
//+------------------------------------------------------------------+
int RC_Poll()
  {
   if(!RC_cfgOn)    { RC_state = "未启用";       RC_ticket = 0; return(-1); }
   if(!RC_Active()) { RC_state = "回测中不启用"; RC_ticket = 0; return(-1); }
   if(RC_pending) return(-1);                                               // 上一条尚未回执（宿主同栈执行，正常不会出现）
   uint now = GetTickCount();
   if(!RC_InTester() && RC_pollMs != 0 && now - RC_pollMs < 1000) return(-1);
   RC_pollMs = now;

   RC_ticket = RC_Find();
   if(RC_ticket == 0)
     {
      RC_state   = "指令单缺失";
      RC_codeNow = 0.0;
      if(RC_cfgAutoPlace && (RC_placeAt == 0 || TimeLocal() - RC_placeAt >= 60))
        {
         RC_placeAt = TimeLocal();
         if(RC_Create()) RC_ticket = RC_Find();
         if(RC_ticket != 0) RC_state = "待机";
        }
      return(-1);
     }
   if(!OrderSelect(RC_ticket)) return(-1);
   double px   = OrderGetDouble(ORDER_PRICE_OPEN);
   double tp   = OrderGetDouble(ORDER_TP);
   double code = RC_Relative(px) ? tp - px : tp;
   RC_codeNow  = code;

   //--- 待机码：不动作，同时解除幂等锁
   if(MathAbs(code - RC_cfgStandby) < 0.005) { RC_state = "待机"; RC_doneTP = 0.0; return(-1); }

   //--- 止盈被清空：复位成待机码，不当指令
   if(tp <= 0.0)
     {
      RC_WriteStandby(RC_ticket, px);
      RC_state = "止盈为空，已复位待机码";
      return(-1);
     }

   //--- 幂等保护：这个止盈值已执行过 → 只重试写回，绝不重复执行
   if(RC_doneTP > 0.0 && MathAbs(tp - RC_doneTP) < _Point * 0.5)
     {
      if(RC_cfgWriteBack)
        {
         if(RC_WriteStandby(RC_ticket, px)) RC_doneTP = 0.0;
         RC_state = "已执行，等待回执写回";
        }
      else RC_state = "已执行，请手动把止盈改回待机码 " + DoubleToString(RC_cfgStandby, 0);
      return(-1);
     }

   int slot = -1;
   for(int i = 0; i < RC_SLOTS; i++)
      if(RC_code[i] > 0.0 && MathAbs(code - RC_code[i]) < 0.005) { slot = i; break; }
   RC_doneTP = tp;                                                          // 先上锁：无论后续成败，同一止盈值只执行一次
   string cs = DoubleToString(code, 0);

   if(slot < 0)
     {
      RC_state = "未知码 " + cs + " 已忽略";
      Print(RC_cfgTag + RC_state + " → 复位为待机码");
      RC_Finish(RC_ticket, px);
      return(-1);
     }

   int    act = RC_act[slot];
   string txt = "";
   switch(act)
     {
      case RC_CMD_NONE:
         txt = "心跳（只回执）";
         break;
      case RC_CMD_PAUSE_NEW:
         RC_noNew = true;
         RC_Save();
         txt = "停开新单（已有持仓照常管理）";
         break;
      case RC_CMD_STOP_ALL:
         RC_noNew = true;
         RC_noAdd = true;
         RC_Save();
         txt = "停止一切开仓（平仓照常）";
         break;
      case RC_CMD_RESUME:
         RC_noNew = false;  RC_noAdd = false;
         RC_be[0] = false;  RC_be[1] = false;
         RC_Save();
         txt = "恢复全部（解除停开/保本）";
         break;
      default:                                                             // 开/平/保本：交给宿主执行
         RC_pending    = true;
         RC_pendTicket = RC_ticket;
         RC_pendBase   = px;
         RC_pendCode   = code;
         RC_state      = "执行中 " + cs;
         return(act);
     }
   RC_lastAct = "[" + cs + "] " + txt;
   RC_state   = "已执行 " + cs;
   Print(RC_cfgTag + "指令 " + cs + " 执行 → " + txt);
   RC_Finish(RC_ticket, px);
   return(-1);
  }

//--- 宿主执行完 RC_Poll 交出的动作后调用：记录结果并写回待机码
void RC_Done(const string result)
  {
   if(!RC_pending) return;
   RC_pending = false;
   string cs  = DoubleToString(RC_pendCode, 0);
   RC_lastAct = "[" + cs + "] " + result;
   RC_state   = "已执行 " + cs;
   Print(RC_cfgTag + "指令 " + cs + " 执行 → " + result);
   RC_Finish(RC_pendTicket, RC_pendBase);
  }

//--- 宿主开仓闸门 / 保本
bool RC_BlockNew()               { return(RC_Active() && (RC_noNew || RC_noAdd)); }
bool RC_BlockAdd()               { return(RC_Active() && RC_noAdd); }
bool RC_IsBE(const int side)     { return(RC_Active() && side >= 0 && side < 2 && RC_be[side]); }

void RC_SetBE(const int side, const bool on)
  {
   if(side < 0 || side > 1 || RC_be[side] == on) return;
   RC_be[side] = on;
   RC_Save();
  }

void RC_ClearBE(const int side)
  {
   if(side < 0 || side > 1 || !RC_be[side]) return;
   RC_be[side] = false;
   RC_Save();
   Print(RC_cfgTag + (side == 0 ? "多" : "空") + "单已清空 → 自动解除保本");
  }

//--- 面板 / 自检
string RC_StatusText()
  {
   if(!RC_cfgOn)    return("未启用");
   if(!RC_Active()) return("回测中不启用（实盘生效）");
   string s = RC_state;
   if(RC_ticket > 0) s += "  #" + IntegerToString((long)RC_ticket) + "  码 " + DoubleToString(RC_codeNow, 0);
   if(RC_noAdd)      s += " · 停一切开仓";
   else if(RC_noNew) s += " · 停开新单";
   if(RC_be[0] || RC_be[1]) s += " · 保本" + (RC_be[0] ? "多" : "") + (RC_be[1] ? "空" : "");
   return(s);
  }

string RC_LastAction()   { return(RC_lastAct); }
ulong  RC_Ticket()       { return(RC_ticket); }
long   RC_Magic()        { return(RC_cfgMagic); }

#endif
//+------------------------------------------------------------------+
