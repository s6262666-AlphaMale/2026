//+------------------------------------------------------------------+
//|                                UI面板核心模块_MT5_v1.3.mqh        |
//|        全视界量化引擎 · 面板骨架层 CPanelEngine · MT5 原生版 v1.3  |
//+------------------------------------------------------------------+
//| v1.3 (MT5 原生): v1.2 内部残留 MQL4 API(AccountBalance/OrdersHistoryTotal/ |
//|   OrderSelect(MODE_HISTORY)/Digits/AccountNumber/StringTrim 返回值),MQL5 编译不过; |
//|   本版改为 AccountInfo*/HistorySelect+HistoryDeal*/_Digits;          |
//|   新增 SetMagicRange(lo,hi): 多魔术号宿主(黄金城 5 套策略)统计已平仓; |
//|   骨架 Y 坐标契约、按钮后缀、接口名与 v1.2 完全一致。              |
//+------------------------------------------------------------------+
//| 源模块: UI面板核心模块_v1.2.mqh (MQL5, 原文件不动)                |
//|                                                                  |
//| 【骨架契约逐字保留】(改一个就会让渲染层与对账台错位)              |
//|   ① 背景板几何: x=10 y=30 宽=panelW-120 高=panelH                |
//|   ② 顶部十三行 Y = 38/64/82/100/120/138/156/174/192/210/228/246/264|
//|   ③ 分区起点 Y=292 (与右侧对账台标题同 Y)                        |
//|   ④ 操作区: 图表最右缘竖列(CORNER_RIGHT_UPPER) 手数框 + 九个按钮   |
//|      按钮后缀: _RBB 买 / _RBS 卖 / _RBC 全平 / _RCB 平多 / _RCS 平空|
//|                _RCP 撤挂单 / _RBA 自检 / _RRST 重置 / _RPSE 暂停   |
//|      手数框: _MLOT                                               |
//|                                                                  |
//| 【MQL5 → MQL4 移植对照】                                         |
//|  · HistorySelect/HistoryDeal* → OrdersHistoryTotal + OrderSelect   |
//|  · AccountInfo*(ACCOUNT_*)   → AccountBalance/Equity/Margin/...    |
//|  · ★MT4 图表文字对象 63 字节上限★(中文按 2 字节):                |
//|    新增 PC_SetLong() —— 长行按 ≤62 字节切段, 每段一个文字对象,    |
//|    用 TextGetSize 实测像素宽首尾相接, 视觉上仍是一整行;          |
//|    MT5 版那些 80~120 字的长行在 MT4 上不被截断                    |
//|  · MT4 中文(GBK)字体缺字的符号替换: ✔→√ ✘→× ▶→◎ ⏸→‖           |
//|  · StringTrimLeft/Right 在 MQL4 返回新串(不改原串)                |
//|  · 新增 ResetStartTime() / ClearLog() (宿主"重置状态"按钮用)      |
//|  · 按钮轮询接口 ButtonCount/ButtonName/ConsumePress 原样保留:     |
//|    MT4 策略测试器同样不派发 OnChartEvent, 可视回测靠轮询点按钮    |
//|                                                                  |
//| 【零交易API】只读账户/历史订单与图表对象, 不发单不改单            |
//+------------------------------------------------------------------+
#ifndef __UI_PANEL_CORE_MT5_V13_MQH__
#define __UI_PANEL_CORE_MT5_V13_MQH__

#define PC_FONT      "Microsoft YaHei"
#define PC_BTN_H     26
#define PC_LOG_STEP  16
#define PC_SEG_MAX   6       // 一行最多切 6 段(≈370 字节)
#define PC_SEG_BYTES 62      // 每段 ≤62 字节(MT4 上限 63)

//+------------------------------------------------------------------+
//| 长行写入: 超过 63 字节自动切段, 段与段按实测像素宽首尾相接         |
//|   基础对象 n 必须已存在(左上角锚); 续段对象名 = n+"~1".."~5"       |
//|   续段继承基础对象的字体/字号/Y; 段数减少时多余续段写空格         |
//+------------------------------------------------------------------+
void PC_SetLong(const string n,string txt,const color c)
  {
   if(ObjectFind(0,n)<0) return;
   if(txt=="") txt=" ";
   string font=ObjectGetString(0,n,OBJPROP_FONT);
   int    fs  =(int)ObjectGetInteger(0,n,OBJPROP_FONTSIZE);
   int    x0  =(int)ObjectGetInteger(0,n,OBJPROP_XDISTANCE);
   int    y0  =(int)ObjectGetInteger(0,n,OBJPROP_YDISTANCE);

   //--- 按字节切段(ASCII 1 字节, 其余按 GBK 2 字节)
   string seg[PC_SEG_MAX];
   int ns=0, len=StringLen(txt), i=0;
   while(i<len && ns<PC_SEG_MAX)
     {
      int b=0, j=i;
      while(j<len)
        {
         int w=(StringGetCharacter(txt,j)<128 ? 1 : 2);
         if(b+w>PC_SEG_BYTES) break;
         b+=w; j++;
        }
      if(j==i) j=i+1;
      seg[ns]=StringSubstr(txt,i,j-i);
      ns++;
      i=j;
     }

   TextSetFont(font,-fs*10);
   int x=x0;
   for(int k=0;k<PC_SEG_MAX;k++)
     {
      string nk=(k==0 ? n : n+"~"+IntegerToString(k));
      if(k>=ns)
        {
         if(k>0 && ObjectFind(0,nk)>=0 && ObjectGetString(0,nk,OBJPROP_TEXT)!=" ") ObjectSetString(0,nk,OBJPROP_TEXT," ");
         continue;
        }
      if(k>0)
        {
         if(ObjectFind(0,nk)<0)
           {
            ObjectCreate(0,nk,OBJ_LABEL,0,0,0);
            ObjectSetInteger(0,nk,OBJPROP_CORNER,CORNER_LEFT_UPPER);
            ObjectSetString (0,nk,OBJPROP_FONT,font);
            ObjectSetInteger(0,nk,OBJPROP_FONTSIZE,fs);
            ObjectSetInteger(0,nk,OBJPROP_SELECTABLE,false);
            ObjectSetInteger(0,nk,OBJPROP_HIDDEN,true);
            ObjectSetInteger(0,nk,OBJPROP_BACK,false);
           }
         ObjectSetInteger(0,nk,OBJPROP_XDISTANCE,x);
         ObjectSetInteger(0,nk,OBJPROP_YDISTANCE,y0);
        }
      if(ObjectGetString(0,nk,OBJPROP_TEXT)!=seg[k]) ObjectSetString(0,nk,OBJPROP_TEXT,seg[k]);
      if((color)ObjectGetInteger(0,nk,OBJPROP_COLOR)!=c) ObjectSetInteger(0,nk,OBJPROP_COLOR,c);
      uint w=0,h=0;
      TextGetSize(seg[k],w,h);
      x+=(int)w;
     }
  }

//+==================================================================+
//|  面板骨架引擎                                                     |
//+==================================================================+
class CPanelEngine
  {
private:
   string            m_pfx;
   int               m_panelW, m_panelH;
   int               m_logRows, m_logCap;
   long              m_magic;
   long              m_magLo, m_magHi;     // [v1.3] 统计魔术号区间(含两端)
   string            m_symbol;
   string            m_title;
   bool              m_verbose;
   bool              m_created;

   bool              m_busy;
   string            m_actObj;
   uint              m_lastRedraw;
   datetime          m_startTime;

   string            m_log[];
   int               m_logCnt;

   int               m_stDeals, m_stWin, m_stLoss;
   double            m_stProfit, m_stBest, m_stWorst;

   string            m_sigSrc, m_sigEntry, m_sigGap, m_sigTrade;

   string            m_btn[];
   int               m_btnN;

   int               BgX() { return(10); }
   int               BgY() { return(30); }
   int               BgW() { int w = m_panelW - 120; return(w < 360 ? 360 : w); }
   int               BgH() { return(m_panelH < 520 ? 520 : m_panelH); }
   int               Cx()  { return(BgX() + 12); }

   void              MkLabel(const string suf, const int x, const int y, const string txt,
                             const color c, const int fs, const string font,
                             const ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER)
     {
      string n = m_pfx + suf;
      if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,     corner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE,  x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE,  y);
      ObjectSetString (0, n, OBJPROP_TEXT,       (txt == "" ? " " : txt));
      ObjectSetInteger(0, n, OBJPROP_COLOR,      c);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE,   fs);
      ObjectSetString (0, n, OBJPROP_FONT,       font);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, n, OBJPROP_BACK,       false);
     }

   void              MkButton(const string suf, const int x, const int y, const int w,
                              const string txt, const color bg, const color fg, const string tip,
                              const ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER)
     {
      string n = m_pfx + suf;
      if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,       corner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
      ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
      ObjectSetInteger(0, n, OBJPROP_YSIZE,        PC_BTN_H);
      ObjectSetString (0, n, OBJPROP_TEXT,         txt);
      ObjectSetString (0, n, OBJPROP_FONT,         PC_FONT);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     9);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
      ObjectSetInteger(0, n, OBJPROP_COLOR,        fg);
      ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, C'70,90,110');
      ObjectSetInteger(0, n, OBJPROP_STATE,        false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN,       true);
      ObjectSetInteger(0, n, OBJPROP_BACK,         false);
      ObjectSetString (0, n, OBJPROP_TOOLTIP,      tip);
      for(int i=0; i<m_btnN; i++) if(m_btn[i] == suf) return;
      ArrayResize(m_btn, m_btnN + 1);
      m_btn[m_btnN] = suf;
      m_btnN++;
     }

   void              MkEdit(const string suf, const int x, const int y, const int w,
                            const string txt, const string tip,
                            const ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER)
     {
      string n = m_pfx + suf;
      if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER,       corner);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
      ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
      ObjectSetInteger(0, n, OBJPROP_YSIZE,        PC_BTN_H - 2);
      ObjectSetString (0, n, OBJPROP_TEXT,         txt);
      ObjectSetString (0, n, OBJPROP_FONT,         "Consolas");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     10);
      ObjectSetInteger(0, n, OBJPROP_ALIGN,        ALIGN_CENTER);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      C'240,240,240');
      ObjectSetInteger(0, n, OBJPROP_COLOR,        clrBlack);
      ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, C'70,90,110');
      ObjectSetInteger(0, n, OBJPROP_READONLY,     false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN,       true);
      ObjectSetString (0, n, OBJPROP_TOOLTIP,      tip);
     }

   void              RenderLog()
     {
      for(int i=0; i<m_logRows; i++)
        {
         int src = m_logCnt - m_logRows + i;      // 旧→新自上而下
         string t = (src >= 0 && src < m_logCnt) ? m_log[src % m_logCap] : "";
         SetLine("_LG" + IntegerToString(i), t, C'150,180,210');
        }
     }

public:
                     CPanelEngine(const string pfx, const int panelW, const int panelH,
                                  const int logRows, const int logCap, const long magic)
     {
      m_pfx      = (pfx == "" ? "SPNL" : pfx);
      m_panelW   = (panelW  > 0 ? panelW  : 680);
      m_panelH   = (panelH  > 0 ? panelH  : 870);
      m_logRows  = (logRows > 0 ? logRows : 6);
      m_logCap   = (logCap  > m_logRows ? logCap : m_logRows * 4);
      m_magic    = magic;
      m_magLo    = magic;
      m_magHi    = magic;
      m_symbol   = Symbol();
      m_title    = "★ 全视界量化引擎 · ";
      m_verbose  = true;
      m_created  = false;
      m_busy     = false;
      m_actObj   = "";
      m_lastRedraw = 0;
      m_startTime  = TimeCurrent();
      m_logCnt   = 0;
      ArrayResize(m_log, m_logCap);
      for(int i=0; i<m_logCap; i++) m_log[i] = "";
      m_stDeals = 0; m_stWin = 0; m_stLoss = 0;
      m_stProfit = 0.0; m_stBest = 0.0; m_stWorst = 0.0;
      m_sigSrc = ""; m_sigEntry = ""; m_sigGap = ""; m_sigTrade = "";
      m_btnN = 0; ArrayResize(m_btn, 0);
     }
                    ~CPanelEngine(void) { }

   void              SetSymbolFilter(const string s) { m_symbol = (s == "" ? Symbol() : s); }
   void              SetMagicRange(const long lo, const long hi) { m_magLo = (lo < hi ? lo : hi); m_magHi = (lo < hi ? hi : lo); }
   void              SetVerbose(const bool v)        { m_verbose = v; }
   void              SetTitle(const string t)        { m_title = t; }
   datetime          GetStartTime(void)              { return(m_startTime); }
   void              ResetStartTime(void)            { m_startTime = TimeCurrent(); }      // [MT4] 新增
   string            Prefix(void)                    { return(m_pfx); }
   bool              IsBusy(void)                    { return(m_busy); }
   int               PanelW(void)                    { return(m_panelW); }
   int               PanelH(void)                    { return(m_panelH); }

   //+---------------------------------------------------------------+
   //| 建面板 —— Y 坐标是与渲染层/对账台的硬契约                      |
   //+---------------------------------------------------------------+
   void              CreatePanel(void)
     {
      Cleanup();
      m_btnN = 0; ArrayResize(m_btn, 0);
      int x = BgX(), y = BgY(), w = BgW(), h = BgH(), cx = Cx();

      string bg = m_pfx + "_BG";
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   x);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   y);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE,       w);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE,       h);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     C'20,29,38');
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR,       C'60,80,100');
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      true);
      ObjectSetInteger(0, bg, OBJPROP_BACK,        false);

      //══ ① 顶部十三行(Y 坐标锁死·对账台逐行对齐) ══
      MkLabel("_T",     cx,  38, "", clrGold,        13, PC_FONT);
      MkLabel("_TIME",  cx,  64, "", C'160,170,180',  9, PC_FONT);
      MkLabel("_BAL",   cx,  82, "", clrLime,         9, PC_FONT);
      MkLabel("_TPNL",  cx, 100, "", clrYellow,      11, PC_FONT);
      MkLabel("_PNL",   cx, 120, "", C'160,170,180',  9, PC_FONT);
      MkLabel("_MDD",   cx, 138, "", clrTomato,       9, PC_FONT);
      MkLabel("_GS",    cx, 156, "", clrOrange,       9, PC_FONT);
      MkLabel("_TRAIL", cx, 174, "", clrGold,         9, PC_FONT);
      MkLabel("_RECY",  cx, 192, "", clrAqua,         9, PC_FONT);
      MkLabel("_ML",    cx, 210, "", clrCyan,         9, PC_FONT);
      MkLabel("_RC",    cx, 228, "", C'200,160,255',  9, PC_FONT);
      MkLabel("_SCAN",  cx, 246, "", clrGold,         9, PC_FONT);
      MkLabel("_CD",    cx, 264, "", C'180,200,220',  9, PC_FONT);

      //══ ② 分区(起点 292·与对账台标题同 Y) ══
      MkLabel("_AH",      cx, 292, "", clrWhite,       11, PC_FONT);
      MkLabel("_FSN_H",   cx, 314, "", clrAqua,        10, PC_FONT);
      MkLabel("_FSN_1",   cx, 332, "", C'170,200,230',  9, PC_FONT);
      MkLabel("_FSN_2",   cx, 348, "", C'170,200,230',  9, PC_FONT);
      MkLabel("_T1_H",    cx, 368, "", clrDodgerBlue,  10, PC_FONT);
      MkLabel("_T1_1",    cx, 386, "", C'160,190,220',  9, PC_FONT);
      MkLabel("_T2_H",    cx, 406, "", clrDodgerBlue,  10, PC_FONT);
      MkLabel("_T2_1",    cx, 424, "", C'120,180,255',  9, PC_FONT);
      MkLabel("_T2_2",    cx, 440, "", C'100,160,235',  9, PC_FONT);
      MkLabel("_T3_H",    cx, 460, "", clrAqua,        10, PC_FONT);
      MkLabel("_T3_1",    cx, 478, "", C'160,190,220',  9, PC_FONT);
      MkLabel("_T3_2",    cx, 494, "", C'160,170,180',  9, PC_FONT);
      MkLabel("_BULL_H",  cx, 514, "", clrAqua,        10, PC_FONT);
      MkLabel("_BULL_1",  cx, 532, "", C'160,170,180',  9, PC_FONT);
      MkLabel("_BULL_2",  cx, 548, "", C'160,170,180',  9, PC_FONT);
      MkLabel("_BEAR_H",  cx, 568, "", clrAqua,        10, PC_FONT);
      MkLabel("_BEAR_1",  cx, 586, "", C'160,170,180',  9, PC_FONT);
      MkLabel("_BEAR_2",  cx, 602, "", C'160,170,180',  9, PC_FONT);
      MkLabel("_TRD_H",   cx, 622, "", clrGold,        10, PC_FONT);
      MkLabel("_TRD_1",   cx, 640, "", C'150,190,240',  9, PC_FONT);
      MkLabel("_TRD_2",   cx, 656, "", C'170,180,190',  9, PC_FONT);
      MkLabel("_FINAL_H", cx, 676, "", clrWhite,       10, PC_FONT);
      MkLabel("_FINAL_1", cx, 694, "", clrLime,         9, PC_FONT);
      MkLabel("_FINAL_2", cx, 710, "", C'190,190,190',  9, PC_FONT);

      //══ ③ 日志区 ══
      MkLabel("_LOGH",    cx, 732, "", clrWhite,       10, PC_FONT);
      for(int i=0; i<m_logRows; i++)
         MkLabel("_LG" + IntegerToString(i), cx, 750 + i * PC_LOG_STEP, "", C'150,180,210', 9, PC_FONT);

      //══ ④ 操作区 · 图表最右缘竖列 ══
      int OPW  = 96;
      int OPX  = 34;
      int OPY  = 78;
      int OPS  = 32;
      int OPB  = OPY + 50;

      string obg = m_pfx + "_OPBG";
      if(ObjectFind(0, obg) < 0) ObjectCreate(0, obg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obg, OBJPROP_CORNER,      CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, obg, OBJPROP_XDISTANCE,   OPX + OPW + 6);
      ObjectSetInteger(0, obg, OBJPROP_YDISTANCE,   OPY - 8);
      ObjectSetInteger(0, obg, OBJPROP_XSIZE,       OPW + 12);
      ObjectSetInteger(0, obg, OBJPROP_YSIZE,       (OPB + 9 * OPS - 6) - (OPY - 8) + 8);
      ObjectSetInteger(0, obg, OBJPROP_BGCOLOR,     C'20,29,38');
      ObjectSetInteger(0, obg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, obg, OBJPROP_COLOR,       C'60,80,100');
      ObjectSetInteger(0, obg, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, obg, OBJPROP_HIDDEN,      true);
      ObjectSetInteger(0, obg, OBJPROP_BACK,        false);

      MkLabel ("_LOTL", OPX + OPW, OPY,      "手动手数", C'200,210,220', 9, PC_FONT, CORNER_RIGHT_UPPER);
      MkEdit  ("_MLOT", OPX + OPW, OPY + 18, OPW, "0",
               "手动下单手数: 填 0 或留空 = 按手数表第1层; 填 >0 = 本次用此手数(仍受人工单单笔最大手数约束)",
               CORNER_RIGHT_UPPER);

      MkButton("_RBB",  OPX + OPW, OPB + 0 * OPS, OPW, "手动买入",  C'25,80,160',  clrWhite, "人工单开多(独立魔术号, 计入整篮止盈)", CORNER_RIGHT_UPPER);
      MkButton("_RBS",  OPX + OPW, OPB + 1 * OPS, OPW, "手动卖出",  C'150,45,45',  clrWhite, "人工单开空(独立魔术号, 计入整篮止盈)", CORNER_RIGHT_UPPER);
      MkButton("_RBC",  OPX + OPW, OPB + 2 * OPS, OPW, "全部平仓",  C'110,60,110', clrWhite, "平掉本EA全部真实持仓, 并清空虚拟篮", CORNER_RIGHT_UPPER);
      MkButton("_RCB",  OPX + OPW, OPB + 3 * OPS, OPW, "平多单",    C'35,75,120',  clrWhite, "只平真实多单", CORNER_RIGHT_UPPER);
      MkButton("_RCS",  OPX + OPW, OPB + 4 * OPS, OPW, "平空单",    C'120,55,55',  clrWhite, "只平真实空单", CORNER_RIGHT_UPPER);
      MkButton("_RCP",  OPX + OPW, OPB + 5 * OPS, OPW, "撤销挂单",  C'70,70,70',   clrWhite, "撤销本EA本品种挂单", CORNER_RIGHT_UPPER);
      MkButton("_RBA",  OPX + OPW, OPB + 6 * OPS, OPW, "状态自检",  C'40,70,100',  clrWhite, "开仓许可 / 首单方向 / 虚拟账本 / 开单诊断 写入日志", CORNER_RIGHT_UPPER);
      MkButton("_RRST", OPX + OPW, OPB + 7 * OPS, OPW, "重置状态",  C'90,90,40',   clrWhite, "运行统计与面板日志归零", CORNER_RIGHT_UPPER);
      MkButton("_RPSE", OPX + OPW, OPB + 8 * OPS, OPW, "暂停/恢复", C'100,80,30',  clrWhite, "暂停只停新开与加仓, 已有持仓照常由出场管理器管理", CORNER_RIGHT_UPPER);

      m_created = true;
      ChartRedraw();
     }

   void              Cleanup(void)
     {
      ObjectsDeleteAll(0, m_pfx);
      m_created = false;
     }

   //================ 填字(长行自动切段) ================
   void              SetLine(const string suf, const string txt, const color c)
     {
      PC_SetLong(m_pfx + suf, txt, c);
     }

   void              SetSignalInfo(const string src, const string entry,
                                   const string gapTxt, const string tradeTxt)
     {
      m_sigSrc = src; m_sigEntry = entry; m_sigGap = gapTxt; m_sigTrade = tradeTxt;
      SetLine("_FSN_1", entry, C'170,200,230');
      SetLine("_FSN_2", "[" + src + "] " + tradeTxt,
              (src == "MIXED" || src == "HALT") ? clrTomato : (src == "PAUSE" ? clrGold : C'150,200,170'));
      SetLine("_T1_1",  gapTxt, C'160,190,220');
     }

   void              LogMessage(const string t)
     {
      if(t == "") return;
      string line = TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS) + " " + t;
      m_log[m_logCnt % m_logCap] = line;
      m_logCnt++;
      RenderLog();
      if(m_verbose) Print("[面板] ", t);
      ThrottledRedraw(false);
     }

   void              ClearLog(void)                                                    // [MT4] 新增
     {
      for(int i=0; i<m_logCap; i++) m_log[i] = "";
      m_logCnt = 0;
      RenderLog();
     }

   //--- 已平统计(只读历史成交 · MT5: 一笔 OUT/INOUT 成交 = 一次平仓)
   void              UpdateOrderStatistics(const datetime from)
     {
      m_stDeals = 0; m_stWin = 0; m_stLoss = 0;
      m_stProfit = 0.0; m_stBest = 0.0; m_stWorst = 0.0;
      datetime a = (from > 0 ? from : m_startTime);
      if(!HistorySelect(a, TimeCurrent() + 86400)) return;
      int n = HistoryDealsTotal();
      for(int i = n - 1; i >= 0; i--)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0) continue;
         long mg = HistoryDealGetInteger(d, DEAL_MAGIC);
         if(mg < m_magLo || mg > m_magHi) continue;
         if(HistoryDealGetString(d, DEAL_SYMBOL) != m_symbol) continue;
         ENUM_DEAL_ENTRY en = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
         if(en != DEAL_ENTRY_OUT && en != DEAL_ENTRY_INOUT && en != DEAL_ENTRY_OUT_BY) continue;
         double p = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP)
                  + HistoryDealGetDouble(d, DEAL_COMMISSION);
         m_stDeals++;
         m_stProfit += p;
         if(p > 0.0) m_stWin++; else if(p < 0.0) m_stLoss++;
         if(p > m_stBest)  m_stBest  = p;
         if(p < m_stWorst) m_stWorst = p;
        }
     }

   double            ClosedProfit(void) { return(m_stProfit); }
   int               ClosedDeals(void)  { return(m_stDeals);  }

   //--- 主刷新: 顶部账户视图
   void              UpdatePanel(const int buyCnt, const int sellCnt, const int pendCnt,
                                 const double floatPL, const double maxDD, const bool mixed,
                                 const double blackLine, const double redLine,
                                 const bool tpArmed, const bool slArmed,
                                 const string scanState, const string lastAction,
                                 const bool paused, const string riskMode,
                                 const int tfMinutes, const double basketMargin)
     {
      if(!m_created) return;

      double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
      double used = AccountInfoDouble(ACCOUNT_MARGIN);
      double fre  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double lvl  = (used > 0.0 ? eq / used * 100.0 : 0.0);
      int    tot  = m_stWin + m_stLoss;
      double wr   = (tot > 0 ? m_stWin * 100.0 / tot : 0.0);
      long   up   = (long)(TimeCurrent() - m_startTime);

      SetLine("_T", m_title + m_symbol + " · " + IntegerToString(tfMinutes) + "分"
              + (paused ? "  【已暂停】" : "") + (mixed ? "  【多空混合】" : ""),
              (mixed ? clrTomato : clrGold));

      SetLine("_TIME", StringFormat("服务器 %s | 运行 %02d:%02d:%02d | 账户 %d %s | 杠杆 1:%d | 魔术号 %I64d",
              TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
              (int)(up/3600), (int)((up%3600)/60), (int)(up%60),
              (int)AccountInfoInteger(ACCOUNT_LOGIN), AccountInfoString(ACCOUNT_CURRENCY), (int)AccountInfoInteger(ACCOUNT_LEVERAGE), m_magic),
              C'160,170,180');

      SetLine("_BAL", StringFormat("【真实】维持率 %.0f%%  已用 %.2f  可用 %.2f  ‖ 余额 %.2f  净值 %.2f",
              lvl, used, fre, bal, eq),
              ((used > 0.0 && lvl > 0.0 && lvl < 300.0) ? clrTomato : clrLime));

      SetLine("_TPNL", StringFormat("★★ 真实已平盈亏: %s%.2f  |  已平仓: %d笔  |  胜率: %.2f%%",
              (m_stProfit >= 0.0 ? "+" : ""), m_stProfit, m_stDeals, wr),
              (m_stProfit > 0.0 ? clrLime : (m_stProfit < 0.0 ? clrRed : clrYellow)));

      SetLine("_PNL", StringFormat("【真实】已平 %s%.2f 浮动 %s%.2f 合计 %s%.2f ‖ 最好 +%.2f 最差 %.2f",
              (m_stProfit >= 0.0 ? "+" : ""), m_stProfit,
              (floatPL   >= 0.0 ? "+" : ""), floatPL,
              (m_stProfit + floatPL >= 0.0 ? "+" : ""), m_stProfit + floatPL,
              m_stBest, m_stWorst),
              C'160,170,180');

      SetLine("_MDD", StringFormat("【本EA】浮亏峰值 -%.2f  ‖  当前浮动 %s%.2f",
              maxDD, (floatPL >= 0.0 ? "+" : ""), floatPL),
              (maxDD > 0.0 ? clrTomato : C'160,170,180'));

      SetLine("_ML", StringFormat("真实持仓: 多%d 空%d 挂单%d | 浮动 %s%.2f | 本篮预付款 $%.2f%s",
              buyCnt, sellCnt, pendCnt, (floatPL >= 0.0 ? "+" : ""), floatPL, basketMargin,
              (mixed ? "  ★多空混合★" : "")),
              (mixed ? clrTomato : (floatPL >= 0.0 ? clrCyan : clrTomato)));

      SetLine("_RC", StringFormat("服务器保护: 止盈线 %s%s | 止损线 %s%s | 风控 %s",
              (redLine   > 0.0 ? DoubleToString(redLine,   _Digits) : "—"), (tpArmed ? "√" : "×"),
              (blackLine > 0.0 ? DoubleToString(blackLine, _Digits) : "—"), (slArmed ? "√" : "×"),
              riskMode),
              ((tpArmed || slArmed) ? C'200,160,255' : clrOrange));

      SetLine("_SCAN", scanState + " | 最近动作: " + (lastAction == "" ? "—" : lastAction),
              (paused ? clrGold : C'200,200,140'));
     }

   //================ 交互 ================
   bool              BeginAction(const string obj)
     {
      if(m_busy)
        {
         ObjectSetInteger(0, obj, OBJPROP_STATE, false);
         ChartRedraw();
         return(false);
        }
      m_busy   = true;
      m_actObj = obj;
      return(true);
     }

   void              EndAction(void)
     {
      if(m_actObj != "" && ObjectFind(0, m_actObj) >= 0)
         ObjectSetInteger(0, m_actObj, OBJPROP_STATE, false);
      m_actObj = "";
      m_busy   = false;
      ChartRedraw();
     }

   double            GetManualLots(const double def)
     {
      string n = m_pfx + "_MLOT";
      if(ObjectFind(0, n) < 0) return(def);
      string s = ObjectGetString(0, n, OBJPROP_TEXT);
      StringTrimRight(s);                                    // [v1.3] MQL5: 原地修改,返回值是个数
      StringTrimLeft(s);
      if(s == "") return(def);
      double v = StringToDouble(s);
      if(v <= 0.0) return(def);
      return(v);
     }

   void              SetManualLots(const double v)
     {
      string n = m_pfx + "_MLOT";
      if(ObjectFind(0, n) >= 0) ObjectSetString(0, n, OBJPROP_TEXT, DoubleToString(v, 2));
     }

   void              SetPauseButtonText(const bool paused)
     {
      string n = m_pfx + "_RPSE";
      if(ObjectFind(0, n) < 0) return;
      string t = (paused ? "◎ 恢复EA" : "‖ 暂停EA");
      if(ObjectGetString(0, n, OBJPROP_TEXT) != t) ObjectSetString(0, n, OBJPROP_TEXT, t);
      ObjectSetInteger(0, n, OBJPROP_BGCOLOR, (paused ? C'140,100,20' : C'100,80,30'));
     }

   //--- 按钮轮询接口(测试器不派发 OnChartEvent 时的唯一通路)
   int               ButtonCount(void) { return(m_btnN); }
   string            ButtonName(const int i)
     { return((i >= 0 && i < m_btnN) ? m_pfx + m_btn[i] : ""); }

   bool              ConsumePress(const string name)
     {
      if(name == "" || ObjectFind(0, name) < 0) return(false);
      if(ObjectGetInteger(0, name, OBJPROP_STATE) == 0) return(false);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
      return(true);
     }

   void              ThrottledRedraw(const bool force)
     {
      uint now = GetTickCount();
      if(!force && now - m_lastRedraw < 100) return;
      m_lastRedraw = now;
      ChartRedraw();
     }
  };

#endif // __UI_PANEL_CORE_MT5_V13_MQH__
//+------------------------------------------------------------------+
