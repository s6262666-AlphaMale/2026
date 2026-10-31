//+------------------------------------------------------------------+
//|                              UI面板独立模块_MT5_v2.7.mqh          |
//|   全视界量化引擎 · 渲染层(双栏: 左真实 / 右虚拟影子账户+同层对账台)|
//|                              MT4 原生移植版                       |
//+------------------------------------------------------------------+
//| 源模块: UI面板独立模块_v2.6.mqh (MQL5 / Sentry机器人 3.9.5, 原文件不动)|
//|                                                                  |
//| 【布局与机制逐项保留】                                           |
//|  · 左栏: 骨架层 CPanelEngine(UI面板核心模块_MT5_v1.2) 顶部十三行  |
//|          + 八个分区 + 日志; 操作区在图表最右缘竖列                |
//|  · 右栏: 紧贴左栏右缘(x = 10 + 面板宽-120), 定宽 450px:           |
//|      ① 虚拟影子账户镜像区 13 行, 与左栏逐行同 Y(左真实 / 右虚拟)   |
//|      ② 同层对账台: 标题 + 汇总 8 行 + 列头 + 逐层明细表           |
//|         (第 i 层虚拟单 ↔ 它镜像出来的真实单, 核验手数是否合梯)    |
//|  · 等宽中文字体实测挑选(NSimSun/新宋体/SimSun/...), 不过测退英文   |
//|  · 明细每行拆 A虚拟/B真实/C核验 三个文字对象(绕开 63 字节上限)    |
//|  · 轮次着色: 同一轮订单同色、换轮换色; 真实持仓开仓点画轮次箭头    |
//|  · 图表线: 真实篮 止盈线/止损线/均价/下次加仓; 虚拟篮 红线/黑线/均价|
//|  · 回测非可视模式整块跳过(零开销, 不影响交易)                     |
//|                                                                  |
//| 【与源模块不同之处 · 为什么】                                    |
//|  源模块的文字内容是 Sentry 专属概念(AMA参照/ρ结构/生存半径/反手/    |
//|  回收赤字/间距引擎), 宿主须实现 24 个同名取数函数。量子黄金没有这些 |
//|  机制 —— 硬接只会让面板对着用户报一堆不存在的数(源模块 v2.2/v2.4   |
//|  自己就在切除这种"死显示")。因此:                                |
//|   · 24 个宿主契约函数 + #define 别名表 → 删除;                    |
//|   · SPanelFeed 改为量子黄金口径(真实篮/决策篮/虚拟接管/出场/许可/   |
//|     周五避险/遥控/逐层明细), 宿主每次刷新填好再调 UiRender();     |
//|   · 各行文字改报量子黄金的真实机制, 版式/颜色/位置照原样.         |
//|  · MT4 API: POSITION_TYPE_* → UI_OP_BUY/UI_OP_SELL, SymbolInfo → MarketInfo,|
//|    长行经 PC_SetLong 切段(MT4 63 字节上限), 缺字符号换 √ × ◆ ◎    |
//|  · 源模块唯一的 input(图表线外观)改为 UiSetLineStyle() 由宿主传入   |
//+------------------------------------------------------------------+
//| 【v2.7 · MT5 原生 + 宿主覆写通道】                               |
//|  · v2.6 仍残留 MQL4 预定义变量 Ask/Bid/Digits、OP_BUY/OP_SELL、    |
//|    IsTesting/IsVisualMode, MQL5 编译不过 → 全部换成 MQL5 等价写法   |
//|  · 新增「宿主覆写通道」(altOn): 非马丁宿主(如黄金城五策略挂单系统)|
//|    可用 UiAltTitle/UiAltSection/UiOverride/UiAltMirror/UiAltBoard*  |
//|    填入自己的真实机制文字, 版式/颜色/Y 坐标契约完全不变;            |
//|    altOn=false 时与 v2.6 逐行同输出                                |
//|  · 票号统一为 long (MT5 单号可超出 int)                            |
//+------------------------------------------------------------------+
#ifndef __UI_PANEL_RENDER_MT5_V27_MQH__
#define __UI_PANEL_RENDER_MT5_V27_MQH__

#define UI_OP_BUY  0     // [v2.7] MQL5 无 UI_OP_BUY/UI_OP_SELL 常量,模块自带
#define UI_OP_SELL 1

#include "UI面板核心模块_MT5_v1.3.mqh"

//==================== 界面固定量(与源模块出厂一致) ====================
const bool   InpShowPanel    = true;
const bool   InpDrawLine     = true;
const int    InpPanelW       = 680;    // 左栏 BG 宽 = 本值-120, 右栏紧贴其右缘
const int    InpPanelH       = 870;
const color  InpBuyColor     = clrDodgerBlue;
const color  InpSellColor    = clrRed;
const int    InpVBRowFont    = 8;
const bool   InpVBHeaderCN   = true;
const string InpVBRowFontCN  = "NSimSun";
const int    InpVBBoardW     = 450;
const int    InpVBCols       = 3;      // ③极简档(去时间/去票号)
const bool   InpVBAutoShrink = true;
const bool   InpRoundColorOn = true;
const bool   InpRoundArrow   = true;

const bool VB_HIDE_GRID  = true;
const bool VB_BOARD_ON   = true;
const int  VB_BOARD_W    = 360;
const int  VB_BOARD_ROWS = 40;
const int  VB_BOARD_FONT = 9;
const int  VB_CHK_WANT   = 14;
#define VB_SUM_ROWS 8

color VB_ROUND_PAL[8] =
  {
   C'120,220,255', C'255,190, 90', C'150,240,150', C'255,150,220',
   C'200,180,255', C'255,230,120', C'140,255,220', C'255,160,130'
  };
string VB_ROUND_NAME[8] = {"天蓝","琥珀","薄荷绿","品红","淡紫","柠檬黄","青绿","珊瑚"};

double UiAsk() { return(SymbolInfoDouble(_Symbol, SYMBOL_ASK)); }   // [v2.7] MQL4 预定义变量 Ask 的 MQL5 等价
double UiBid() { return(SymbolInfoDouble(_Symbol, SYMBOL_BID)); }   // [v2.7] MQL4 预定义变量 Bid 的 MQL5 等价

//==================== 宿主喂数结构(量子黄金口径) ====================
struct SPanelLeg
  {
   bool     has;
   int      dir;       // 1=多 -1=空
   double   lot;
   double   open;
   datetime tm;
   double   pl;
   long     ticket;
   int      round;
   double   expLot;    // 本层按梯应有手数(核验用; 0=不核验)
  };

struct SPanelFeed
  {
   //--- 运行环境
   bool      inTester;
   bool      visualMode;
   string    verTag;          // 面板抬头版本号
   int       tfMin;
   long      magic;
   double    pt;              // Point

   //--- 执行面: 真实篮(策略单 + 人工单)
   int       rBuy, rSell, rCnt;
   double    rTotLot, rAvg, rPL;
   int       rType;           // UI_OP_BUY / UI_OP_SELL / -1
   bool      rMixed;
   double    maxDD;           // 运行以来真实浮亏峰值(正数)
   datetime  maxDDTime;
   double    redLine;         // 真实篮止盈价(服务器TP 或 按金额解出)
   double    blackLine;       // 真实篮止损价
   bool      tpArmed, slArmed;
   bool      serverOn;        // 服务器TP/SL 启用
   double    tpUSD;           // 整篮止盈金额(真实)
   double    slUSD;           // 整篮止损金额(0=关)
   double    basketMargin;

   //--- 决策面(接管开=虚拟篮, 关=真实篮)
   int       cnt, buyCnt, sellCnt, type;   // type: UI_OP_BUY/UI_OP_SELL/-1
   bool      mixed;
   double    totLot, avg, pl, lastOpen, lastLot;
   datetime  lastAddTime;
   int       maxLayers;
   double    nextLot;
   double    nextAddPx;       // 下次逆势加仓价(0=无)
   double    gapPts;          // 当前加仓间隔(点)
   string    gapSrc;          // 间隔来源说明
   int       throttleSec;

   //--- 文字状态(宿主预格式化)
   string    entryTxt;        // 首单方向
   string    sigSrc;          // LIVE / VOM / PAUSE / HALT
   string    permitTxt;       // 开仓许可
   string    blockTxt;        // 最近拦截
   string    exitTxt1, exitTxt2;   // 出场管理器
   string    addRuleTxt;      // 加仓规则
   string    spreadTxt, symTxt;
   string    finalTxt1, finalTxt2;
   string    guardTxt;        // 周五避险 + 遥控
   string    lastAction;
   string    diagTxt;         // 开单诊断摘要
   bool      paused, closing, halted;
   double    spread;

   //--- 虚拟接管(VOM) —— 宿主预取, 本模块不认识 VOM 类
   bool      vomOn;
   int       vCount, vDir;
   double    vVolume, vAvgPrice, vFloat;
   double    vPeakDD, vPeakPF;          // 本篮峰亏(负)/峰盈
   int       vBasketSeq, vClosedBaskets, vMaxLayerEver, vHandoverCount, vRealOpened;
   double    vClosedPL;
   int       vWinCnt, vLossCnt;
   double    vMaxDD;                    // 运行以来虚拟浮亏峰值(正数)
   datetime  vMaxDDTime;
   double    vPeakProfitHist;
   double    vbInitBal;                 // 影子账户起跑线
   double    vMargin;                   // 虚拟持仓假设占用预付款
   double    vRedLine, vBlackLine;      // 虚拟篮止盈/止损价(按金额解出)
   double    vTPUSD, vSLUSD;
   int       handoverLayer, handoverMode, realMaxCount;
   bool      armed;
   int       layersToGo;
   string    lotModeName, linkName, vBlockReason;
   double    commPerLot;
   bool      modelSpread, modelSwap;
   int       realWant;                  // 按闸门真实应有张数

   //--- 逐层明细(宿主填好; rlegs[i] = 第 i 层虚拟单镜像出的真实单, 之后附未配对真实单)
   SPanelLeg vlegs[];
   SPanelLeg rlegs[];

   //--- [v2.7] 宿主覆写通道(非马丁宿主用; altOn=false 时完全不生效)
   bool      altOn;
   string    altTitle;                  // 左栏 _AH 抬头
   string    altSec[9];                 // 九个分区标题(_FSN_H/_T1_H/_T2_H/_T3_H/_BULL_H/_BEAR_H/_TRD_H/_FINAL_H/_LOGH)
   int       ovrN;
   string    ovrKey[40];
   string    ovrTxt[40];
   color     ovrClr[40];
   string    altMirror[13];             // 右栏镜像区 13 行
   color     altMirrorClr[13];
   string    altBoardHead;              // 右栏对账台标题
   string    altSum[8];                 // 右栏汇总 8 行
   color     altSumClr[8];
   string    altColHead;                // 右栏明细列头
   string    altRows[];                 // 右栏明细行
   color     altRowClr[];
  };

//==================== 模块自有状态 ====================
CPanelEngine *g_panel = NULL;
SPanelFeed    g_fd;
string   g_vbPfx      = "SVOMB";
int      g_vbRows     = 0;
uint     g_vbLastTick = 0;
uint     g_lastStatTick = 0;
int      g_vbMode     = 3;
int      g_vbChkCap   = 18;
string   g_vbFont     = "Consolas";
bool     g_vbCNok     = false;
double   g_vbCharW    = 0.0;
string   g_objRdPfx   = "QGUI_RD_";
int      g_roundNo    = 1;
datetime g_roundStart = 0;
datetime g_rndT[16];
string   g_uiGV       = "QGUI_RND_";
string   g_objLine  = "QGUI_止盈线";
string   g_objBlack = "QGUI_止损线";
string   g_objAvg   = "QGUI_均价线";
string   g_objNext  = "QGUI_下次加仓线";
string   g_objVRed  = "QGUI_虚拟红线";
string   g_objVBlk  = "QGUI_虚拟黑线";
string   g_objVAvg  = "QGUI_虚拟均价";
color           g_lnTPColor = C'190,120,255';
int             g_lnTPWidth = 1;
ENUM_LINE_STYLE g_lnTPStyle = STYLE_SOLID;
color           g_lnSLColor = C'255,120,60';
int             g_lnSLWidth = 1;
ENUM_LINE_STYLE g_lnSLStyle = STYLE_SOLID;

int UiLineW(const int w) { return(w < 1 ? 1 : (w > 5 ? 5 : w)); }

//==================== 纯工具层(逐字搬自源模块) ====================
int DispCh(ushort c)
  {
   if(c >= 0x1100 &&
      (c <= 0x115F ||
       (c >= 0x2E80 && c <= 0xA4CF && c != 0x303F) ||
       (c >= 0xAC00 && c <= 0xD7A3) ||
       (c >= 0xF900 && c <= 0xFAFF) ||
       (c >= 0xFE30 && c <= 0xFE6F) ||
       (c >= 0xFF00 && c <= 0xFF60) ||
       (c >= 0xFFE0 && c <= 0xFFE6)))
      return(2);
   return(1);
  }

int DispW(string t)
  {
   int w = 0, l = StringLen(t);
   for(int i=0; i<l; i++) w += DispCh(StringGetCharacter(t, i));
   return(w);
  }

string CutR(string t, int n)
  {
   int i = StringLen(t) - 1, w = 0;
   while(i >= 0)
     {
      int d = DispCh(StringGetCharacter(t, i));
      if(w + d > n) break;
      w += d; i--;
     }
   return(StringSubstr(t, i+1));
  }

string CutL(string t, int n)
  {
   int i = 0, w = 0, l = StringLen(t);
   while(i < l)
     {
      int d = DispCh(StringGetCharacter(t, i));
      if(w + d > n) break;
      w += d; i++;
     }
   return(StringSubstr(t, 0, i));
  }

string PadL(string t, int n)
  {
   string r = CutR(t, n), pad = "";
   for(int i=DispW(r); i<n; i++) pad += " ";
   return(pad + r);
  }

string PadR(string t, int n)
  {
   string r = CutL(t, n), pad = "";
   for(int i=DispW(r); i<n; i++) pad += " ";
   return(r + pad);
  }

string ShortT(string t)
  {
   int l = StringLen(t);
   return(l > 5 ? StringSubstr(t, l-5, 5) : t);
  }

int VBFixedChars(int mode)
  {
   if(mode == 2) return(74);
   if(mode == 3) return(62);
   return(104);
  }

int VBSegW(int mode, int seg)
  {
   if(mode == 3) return(seg == 0 ? 32 : 29);
   if(mode == 2) return(seg == 0 ? 38 : 35);
   return(seg == 0 ? 48 : 55);
  }

bool FontIsMono(string f, int sz, bool needCJK, double &charW)
  {
   charW = 0.0;
   if(f == "") return(false);
   if(!TextSetFont(f, -sz*10)) return(false);
   uint wM=0, hM=0, wI=0, hI=0;
   if(!TextGetSize("MMMMMMMM", wM, hM)) return(false);
   if(!TextGetSize("iiiiiiii", wI, hI)) return(false);
   if(wM == 0 || wM != wI) return(false);
   charW = (double)wM / 8.0;
   if(!needCJK) return(true);
   uint wC=0, hC=0;
   if(!TextGetSize("中中中中", wC, hC)) return(false);
   return(wC == wM);
  }

void PickBoardFont(int sz)
  {
   g_vbCNok = false; g_vbFont = "Consolas"; g_vbCharW = 0.0;
   double cw = 0.0;
   if(InpVBHeaderCN)
     {
      string cand[8];
      cand[0] = InpVBRowFontCN;
      cand[1] = "NSimSun";
      cand[2] = "新宋体";
      cand[3] = "SimSun";
      cand[4] = "宋体";
      cand[5] = "MS Gothic";
      cand[6] = "Sarasa Mono SC";
      cand[7] = "Courier New";
      for(int i=0; i<8; i++)
        {
         if(cand[i] == "") continue;
         if(FontIsMono(cand[i], sz, true, cw))
           { g_vbFont = cand[i]; g_vbCharW = cw; g_vbCNok = true; break; }
        }
     }
   if(!g_vbCNok)
     {
      string ca[3]; ca[0]="Consolas"; ca[1]="Courier New"; ca[2]="Lucida Console";
      for(int i=0; i<3; i++)
         if(FontIsMono(ca[i], sz, false, cw)) { g_vbFont = ca[i]; g_vbCharW = cw; break; }
      if(g_vbCharW <= 0.0) g_vbCharW = sz * 0.55;
     }
  }

void VBRow3(string sq, string vd, string vl, string vo, string vt, string vp,
            string rd, string rl, string ro, string rt, string rp, string rk, string ck,
            string &oA, string &oB, string &oC)
  {
   string c = (DispW(ck) > g_vbChkCap) ? CutL(ck, g_vbChkCap) : ck;
   if(g_vbMode == 3)
     {
      oA = PadL(sq,3)+"|"+PadR(vd,4)+" "+PadL(vl,5)+" "+PadL(vo,9)+" "+PadL(vp,7);
      oB = "|"+PadR(rd,4)+" "+PadL(rl,5)+" "+PadL(ro,9)+" "+PadL(rp,7);
      oC = "|"+c;
      return;
     }
   if(g_vbMode == 2)
     {
      oA = PadL(sq,3)+"|"+PadR(vd,4)+" "+PadL(vl,5)+" "+PadL(vo,9)+" "+PadL(ShortT(vt),5)+" "+PadL(vp,7);
      oB = "|"+PadR(rd,4)+" "+PadL(rl,5)+" "+PadL(ro,9)+" "+PadL(ShortT(rt),5)+" "+PadL(rp,7);
      oC = "|"+c;
      return;
     }
   oA = PadL(sq,3)+"|"+PadR(vd,5)+" "+PadL(vl,5)+" "+PadL(vo,10)+" "+PadL(vt,12)+" "+PadL(vp,8);
   oB = "|"+PadR(rd,5)+" "+PadL(rl,5)+" "+PadL(ro,10)+" "+PadL(rt,12)+" "+PadL(rp,8)+" "+PadL(rk,9);
   oC = "|"+c;
  }

void VBHeader3(string &a, string &b, string &c)
  {
   if(!InpVBHeaderCN || !g_vbCNok)
     { VBRow3("Lyr","V-Dir","V-Lot","V-Open","V-Time","V-PnL",
              "R-Dir","R-Lot","R-Open","R-Time","R-PnL","R-Tkt","Chk", a,b,c); return; }
   if(g_vbMode == 3)
     { VBRow3("层","虚向","虚手","虚开仓价","","虚浮动",
              "真向","真手","真开仓价","","真浮动","","核验", a,b,c); return; }
   if(g_vbMode == 2)
     { VBRow3("层","虚向","虚手","虚开仓价","虚时","虚浮动",
              "真向","真手","真开仓价","真时","真浮动","","核验", a,b,c); return; }
   VBRow3("层","虚向","虚手","虚开仓价","虚开仓时间","虚浮动",
          "真向","真手","真开仓价","真开仓时间","真浮动","真票号","核验", a,b,c);
  }

void VBLabel(string n, int x, int y, string t, color c, int fs, string font)
  {
   ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   if(t == "") t = " ";
   ObjectSetString (0, n, OBJPROP_TEXT, t);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetString (0, n, OBJPROP_FONT, font);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
  }

void VBLabel3(string base, int x, int y, int fs, string font, color c)
  {
   double cw = (g_vbCharW > 0.0 ? g_vbCharW : fs*0.55);
   VBLabel(g_vbPfx+base+"A", x,                                                  y, "", c, fs, font);
   VBLabel(g_vbPfx+base+"B", x+(int)(VBSegW(g_vbMode,0)*cw),                     y, "", c, fs, font);
   VBLabel(g_vbPfx+base+"C", x+(int)((VBSegW(g_vbMode,0)+VBSegW(g_vbMode,1))*cw), y, "", c, fs, font);
  }

//--- 长行(汇总/镜像区)走切段写入; 明细行三段各自都 <63 字节, 直接写
void VBSet(string suf, string t, color c)
  {
   PC_SetLong(g_vbPfx + suf, t, c);
  }

void VBSetShort(string suf, string t, color c)
  {
   string n = g_vbPfx + suf;
   if(ObjectFind(0, n) < 0) return;
   if(t == "") t = " ";
   if(ObjectGetString(0, n, OBJPROP_TEXT) != t) ObjectSetString(0, n, OBJPROP_TEXT, t);
   if((color)ObjectGetInteger(0, n, OBJPROP_COLOR) != c) ObjectSetInteger(0, n, OBJPROP_COLOR, c);
  }

void VBSet3(string base, string a, string b, string c, color col)
  {
   VBSetShort(base+"A", a, col); VBSetShort(base+"B", b, col); VBSetShort(base+"C", c, col);
  }

string VBTime(datetime t)
  {
   if(t <= 0) return("-");
   return(StringSubstr(TimeToString(t, TIME_DATE|TIME_MINUTES), 5));
  }

string VBDirCN(int d) { return(d>0 ? "多" : (d<0 ? "空" : "—")); }
string DirOfType(int t) { return(t==UI_OP_BUY ? "多" : (t==UI_OP_SELL ? "空" : "—")); }

color RoundColor(int rd)
  {
   if(rd < 1) rd = 1;
   return(VB_ROUND_PAL[(rd - 1) % 8]);
  }

string RoundName(int rd)
  {
   if(rd < 1) rd = 1;
   return(VB_ROUND_NAME[(rd - 1) % 8]);
  }

string UiPx(double v) { return(v > 0.0 ? DoubleToString(v, _Digits) : "-"); }
string UiSgn(double v) { return(v >= 0.0 ? "+" : "-"); }

void MakeHLine(string name, double price, color c, int w, ENUM_LINE_STYLE st, string txt)
  {
   if(ObjectFind(0,name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }
   ObjectSetDouble (0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetString (0, name, OBJPROP_TEXT,  txt);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, txt + " " + DoubleToString(price,_Digits));
  }

void VomBoardDelete()    { ObjectsDeleteAll(0, g_vbPfx); g_vbRows = 0; }
void RoundArrowsDelete() { ObjectsDeleteAll(0, g_objRdPfx); }

void DeleteLines()
  {
   ObjectDelete(0, g_objLine);
   ObjectDelete(0, g_objBlack);
   ObjectDelete(0, g_objAvg);
   ObjectDelete(0, g_objNext);
   ObjectDelete(0, g_objVRed);
   ObjectDelete(0, g_objVBlk);
   ObjectDelete(0, g_objVAvg);
  }

//==================== 图表线 ====================
void DrawLines()
  {
   if(!InpDrawLine) { DeleteLines(); return; }

   //--- ① 执行面: 真实篮 止盈线 / 止损线 / 均价
   if(g_fd.rCnt<=0 || g_fd.rMixed)
     {
      ObjectDelete(0, g_objLine);
      ObjectDelete(0, g_objBlack);
      ObjectDelete(0, g_objAvg);
     }
   else
     {
      if(g_fd.redLine > 0.0)
         MakeHLine(g_objLine, g_fd.redLine, g_lnTPColor, UiLineW(g_lnTPWidth), g_lnTPStyle,
                   (g_fd.serverOn ? "整篮止盈线(服务器TP·真实篮)" : "整篮止盈线(EA执行·真实篮)"));
      else ObjectDelete(0, g_objLine);
      if(g_fd.blackLine > 0.0)
         MakeHLine(g_objBlack, g_fd.blackLine, g_lnSLColor, UiLineW(g_lnSLWidth), g_lnSLStyle,
                   (g_fd.serverOn ? "整篮止损线(服务器SL·真实篮)" : "整篮止损线(EA执行·真实篮)"));
      else ObjectDelete(0, g_objBlack);
      MakeHLine(g_objAvg, NormalizeDouble(g_fd.rAvg,_Digits), clrSilver, 1, STYLE_DOT, "真实篮加权均价");
     }

   //--- 下次加仓线属于【决策面】(接管开 = 虚拟篮的下一层)
   if(g_fd.cnt > 0 && !g_fd.mixed && g_fd.nextAddPx > 0.0)
     {
      color c = (g_fd.type==UI_OP_SELL) ? InpSellColor : InpBuyColor;
      MakeHLine(g_objNext, NormalizeDouble(g_fd.nextAddPx,_Digits), c, 1, STYLE_DASH,
                (g_fd.vomOn ? "下次加仓(虚拟决策面)" : "下次加仓"));
     }
   else ObjectDelete(0, g_objNext);

   //--- ② 决策面: 虚拟篮 红线 / 黑线 / 均价
   if(g_fd.vomOn && g_fd.vCount > 0 && g_fd.vDir != 2)
     {
      if(g_fd.vRedLine > 0.0) MakeHLine(g_objVRed, g_fd.vRedLine, C'255,120,120', 1, STYLE_DASHDOT,
                                        StringFormat("虚拟红线(第%d层影子篮·未真实挂单)", g_fd.vCount));
      else ObjectDelete(0, g_objVRed);
      if(g_fd.vBlackLine > 0.0) MakeHLine(g_objVBlk, g_fd.vBlackLine, C'140,140,140', 1, STYLE_DASHDOT, "虚拟黑线(影子篮)");
      else ObjectDelete(0, g_objVBlk);
      MakeHLine(g_objVAvg, NormalizeDouble(g_fd.vAvgPrice,_Digits), C'200,200,120', 1, STYLE_DOT,
                StringFormat("虚拟加权均价(%.2f手)", g_fd.vVolume));
     }
   else
     {
      ObjectDelete(0, g_objVRed);
      ObjectDelete(0, g_objVBlk);
      ObjectDelete(0, g_objVAvg);
     }
  }

//==================== 分区标题 ====================
void RelabelPanel()
  {
   if(g_panel == NULL) return;
   if(g_fd.altOn)
     {
      string keys[9] = {"_FSN_H","_T1_H","_T2_H","_T3_H","_BULL_H","_BEAR_H","_TRD_H","_FINAL_H","_LOGH"};
      color  cols[9] = {clrAqua, clrDodgerBlue, clrDodgerBlue, clrAqua, clrAqua, clrAqua, clrGold, clrWhite, clrWhite};
      g_panel.SetLine("_AH", g_fd.altTitle, (InpRoundColorOn ? RoundColor(g_roundNo) : clrWhite));
      for(int k = 0; k < 9; k++) g_panel.SetLine(keys[k], g_fd.altSec[k], cols[k]);
      return;
     }
   g_panel.SetLine("_AH", StringFormat("═══ 全视界量化引擎 · 量子黄金 %s · 第%d轮(%s) ═══", g_fd.verTag,
                   g_roundNo, RoundName(g_roundNo)),
                   (InpRoundColorOn ? RoundColor(g_roundNo) : clrWhite));
   g_panel.SetLine("_FSN_H",   "▌首单方向 · 开仓依据",           clrAqua);
   g_panel.SetLine("_T1_H",    "▌下单链路 · 加仓间隔与节流",     clrDodgerBlue);
   g_panel.SetLine("_T2_H",    "▌开仓许可 · 阻断证据",           clrDodgerBlue);
   g_panel.SetLine("_T3_H",    "▌篮子出场管理器",                clrAqua);
   g_panel.SetLine("_BULL_H",  "▌点差与品种",                    clrAqua);
   g_panel.SetLine("_BEAR_H",  "▌篮子明细",                      clrAqua);
   g_panel.SetLine("_TRD_H",   (g_fd.vomOn ? "▌虚拟订单接管 VOM · 双平面" : "▌虚拟订单接管 VOM"), clrGold);
   g_panel.SetLine("_FINAL_H", "▌风控执行状态",                  clrWhite);
   g_panel.SetLine("_LOGH",    "═══════════ 系统日志 ═══════════", clrWhite);
  }

//==================== 虚拟影子账户 ====================
double VirtBalance() { return(g_fd.vbInitBal + (g_fd.vomOn ? g_fd.vClosedPL : 0.0)); }
double VirtEquity()  { return(VirtBalance() + ((g_fd.vomOn && g_fd.vCount > 0) ? g_fd.vFloat : 0.0)); }

void VomAccountMirror()
  {
   if(ObjectFind(0, g_vbPfx+"_ABAL") < 0) return;

   if(!g_fd.vomOn && g_fd.altOn)
     {
      string mk[13] = {"_AT","_ATIME","_ABAL","_ATPNL","_APNL","_AMDD","_AGS","_ATRL","_ARECY","_AML","_ARC","_ASCN","_ACD"};
      for(int k = 0; k < 13; k++) VBSet(mk[k], g_fd.altMirror[k], g_fd.altMirrorClr[k]);
      return;
     }
   if(!g_fd.vomOn)
     {
      VBSet("_AT",    "★ 虚拟系统(影子账户) —— 虚拟接管 OFF", C'140,150,160');
      VBSet("_ATIME", "接管关闭: 只有一套系统(全部下单直发券商), 无影子账户可对照。", C'150,160,170');
      string blanks[11] = {"_ABAL","_ATPNL","_APNL","_AMDD","_AGS","_ATRL","_ARECY","_AML","_ARC","_ASCN","_ACD"};
      for(int i=0; i<11; i++) VBSet(blanks[i], "", C'140,150,160');
      VBSet("_ABAL", "打开参数【虚拟接管启用】即可看到左真实 / 右虚拟的逐行对照与同层对账台。", C'150,160,170');
      return;
     }

   double vClosed = g_fd.vClosedPL;
   double vFlt    = (g_fd.vCount > 0 ? g_fd.vFloat : 0.0);
   double vBal    = VirtBalance();
   double vEq     = VirtEquity();
   double vMg     = g_fd.vMargin;
   double vFree   = vEq - vMg;
   double vLvl    = (vMg > 0.0) ? (vEq / vMg * 100.0) : 0.0;
   int    vTot    = g_fd.vWinCnt + g_fd.vLossCnt;
   double vWR     = (vTot > 0) ? (g_fd.vWinCnt * 100.0 / vTot) : 0.0;

   VBSet("_AT", "★ 虚拟系统(影子账户) · 与左侧真实并排对照", clrGold);
   VBSet("_ATIME", StringFormat("虚拟账本: 第%d篮 | 已完成%d篮(盈%d 亏%d) | 最深%d层 | 起跑线 %.0f",
                   g_fd.vBasketSeq, g_fd.vClosedBaskets, g_fd.vWinCnt, g_fd.vLossCnt,
                   g_fd.vMaxLayerEver, g_fd.vbInitBal), C'160,170,180');
   VBSet("_ABAL", StringFormat("【虚拟】维持率 %.0f%%  已用 %.2f  可用 %.2f  ‖ 预付款 %.2f (假设占用)",
                   vLvl, vMg, vFree, vMg),
         ((vMg > 0.0 && vLvl < 300.0) ? clrTomato : clrLime));
   VBSet("_ATPNL", StringFormat("★★ 虚拟已平盈亏: %s%.2f  |  已平仓: %d篮  |  胜率: %.2f%%",
                   (vClosed>=0.0?"+":""), vClosed, g_fd.vClosedBaskets, vWR),
         (vClosed > 0.0 ? clrLime : (vClosed < 0.0 ? clrRed : clrYellow)));
   VBSet("_APNL", StringFormat("【虚拟】净值 %.2f 余额 %.2f  ‖ 已平 %s%.2f 浮动 %s%.2f 合计 %s%.2f",
                   vEq, vBal, (vClosed>=0.0?"+":""), vClosed, (vFlt>=0.0?"+":""), vFlt,
                   (vClosed+vFlt>=0.0?"+":""), vClosed+vFlt), C'160,170,180');
   VBSet("_AMDD", StringFormat("【虚拟】浮亏峰值 -%.2f @%s  ‖  当前浮动 %s%.2f  ‖  峰值浮盈 +%.2f",
                   g_fd.vMaxDD, (g_fd.vMaxDDTime > 0 ? VBTime(g_fd.vMaxDDTime) : "尚未发生"),
                   (vFlt>=0.0?"+":""), vFlt, g_fd.vPeakProfitHist),
         (g_fd.vMaxDD > 0.0 ? clrTomato : C'160,170,180'));

   double vpx = (g_fd.vDir==-1) ? UiAsk() : UiBid();
   VBSet("_AGS", StringFormat("虚拟止损黑线: %s  (距 %.0f点) | 虚拟篮止损 $%.0f",
                   (g_fd.vBlackLine > 0.0 ? DoubleToString(g_fd.vBlackLine,_Digits) : (g_fd.vCount>0 ? (g_fd.vSLUSD>0?"不可达(手数过小)":"未设") : "待命(空篮)")),
                   ((g_fd.vBlackLine > 0.0 && g_fd.pt > 0.0) ? MathAbs(vpx-g_fd.vBlackLine)/g_fd.pt : 0.0),
                   g_fd.vSLUSD), clrOrange);
   VBSet("_ATRL", StringFormat("虚拟平仓红线: %s  (距 %.0f点 / 目标$%.2f)  均价 %s",
                   UiPx(g_fd.vRedLine),
                   ((g_fd.vRedLine > 0.0 && g_fd.pt > 0.0) ? MathAbs(vpx-g_fd.vRedLine)/g_fd.pt : 0.0),
                   g_fd.vTPUSD, (g_fd.vCount > 0 ? DoubleToString(g_fd.vAvgPrice,_Digits) : "-")), clrGold);
   VBSet("_ARECY", StringFormat("切换闸门 第%d层 %s | 切换后%s | 真实手数 %s",
                   g_fd.handoverLayer,
                   (g_fd.handoverLayer<=0 ? "纯记账(不下真实单)" : (g_fd.armed ? "已触发√" : StringFormat("还差%d层", g_fd.layersToGo))),
                   (g_fd.handoverMode==0 ? "只开一张" : "每层跟一张"), g_fd.lotModeName),
         (g_fd.armed ? clrLime : clrAqua));
   VBSet("_AML", StringFormat("虚拟层: %d (多%d 空%d) 总手%.2f | 浮盈 %s%.2f | 本篮峰亏%.2f 峰盈%.2f",
                   g_fd.vCount, g_fd.buyCnt, g_fd.sellCnt, g_fd.vVolume,
                   (vFlt>=0.0?"+":""), vFlt, g_fd.vPeakDD, g_fd.vPeakPF),
         (vFlt>=0.0 ? clrCyan : clrTomato));
   int elV = (g_fd.lastAddTime > 0) ? (int)(TimeCurrent()-g_fd.lastAddTime) : 0;
   VBSet("_ARC", StringFormat("虚拟风控: 间隔%.0f点 节流%d/%ds 层%d/%d | 第%d层 ⇒ %.2f手",
                   g_fd.gapPts, elV, g_fd.throttleSec, g_fd.cnt, g_fd.maxLayers, g_fd.cnt+1, g_fd.nextLot), C'200,160,255');
   VBSet("_ASCN", StringFormat("偏移跟随: 闸门%d(偏移%d) ⇒ 真实应有%d张 / 实有%d张 %s",
                   g_fd.handoverLayer, (g_fd.handoverLayer>0 ? g_fd.handoverLayer-1 : 0),
                   g_fd.realWant, g_fd.rCnt,
                   (g_fd.realWant > g_fd.rCnt ? "待补+" : (g_fd.realWant < g_fd.rCnt ? "超前(虚拟已退)" : "已同步√"))),
         (g_fd.realWant > g_fd.rCnt ? clrGold : C'170,200,190'));
   VBSet("_ACD", StringFormat("虚拟成本: 佣金$%.2f/手(单边) 点差%s 隔夜息%s | 联动 %s",
                   g_fd.commPerLot, (g_fd.modelSpread ? "ON" : "OFF"), (g_fd.modelSwap ? "ON" : "OFF"), g_fd.linkName),
         C'180,200,220');
  }

//==================== 右栏建立 ====================
void VomBoardCreate()
  {
   VomBoardDelete();
   if(!VB_BOARD_ON) return;

   int fs = VB_BOARD_FONT;
   int rfs = InpVBRowFont;
   if(rfs < 6)  rfs = 6;
   if(rfs > 28) rfs = 28;
   PickBoardFont(rfs);

   int x = 10 + (InpPanelW - 120);
   int y = 30;
   int w = InpPanelW - 120;
   if(w < VB_BOARD_W) w = VB_BOARD_W;
   {
    long chW   = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    int  avail = (chW > 0) ? (int)chW - x - 8 : 100000;
    double cw = g_vbCharW;
    if(InpVBBoardW > 0) w = InpVBBoardW;
    if(avail > 200 && w > avail) w = avail;
    if(InpVBCols >= 1 && InpVBCols <= 3) g_vbMode = InpVBCols;
    if(InpVBAutoShrink)
      {
       int guard = 0;
       while(rfs > 6 && guard++ < 32)
         {
          PickBoardFont(rfs); cw = g_vbCharW;
          int need = (int)((VBFixedChars(g_vbMode) + (g_vbMode==1 ? 18 : 16)) * cw) + 28;
          if(need <= w) break;
          rfs--;
         }
       PickBoardFont(rfs); cw = g_vbCharW;
      }
    g_vbChkCap = (int)((w - 28 - 16) / (cw > 0.0 ? cw : 1.0)) - (VBSegW(g_vbMode,0) + VBSegW(g_vbMode,1));
    if(g_vbChkCap < 6)  g_vbChkCap = 6;
    if(g_vbChkCap > 40) g_vbChkCap = 40;
    PrintFormat("【对账台几何】明细字号=%d 板 左缘%d 宽%dpx | 图表可视宽%dpx | 核验列%d字符 | 列头=%s",
                rfs, x, w, (int)chW, g_vbChkCap, (g_vbCNok ? "中文·"+g_vbFont : "英文·"+g_vbFont));
   }
   int h = InpPanelH + 18;

   ObjectCreate(0, g_vbPfx+"_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_XSIZE, w);
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_YSIZE, h);
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_BGCOLOR, C'20,29,38');
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, g_vbPfx+"_BG", OBJPROP_BACK, false);

   int cx = x + 12;
   //══ 一、虚拟影子账户镜像区(Y 与左栏顶部十三行逐行对齐) ══
   VBLabel(g_vbPfx+"_AT",    cx,  38, "", clrGold,        13, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_ATIME", cx,  64, "", C'160,170,180',  9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_ABAL",  cx,  82, "", clrLime,         9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_ATPNL", cx, 100, "", clrYellow,      11, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_APNL",  cx, 120, "", C'160,170,180',  9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_AMDD",  cx, 138, "", clrTomato,       9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_AGS",   cx, 156, "", clrOrange,       9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_ATRL",  cx, 174, "", clrGold,         9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_ARECY", cx, 192, "", clrAqua,         9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_AML",   cx, 210, "", clrCyan,         9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_ARC",   cx, 228, "", C'200,160,255',  9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_ASCN",  cx, 246, "", clrGold,         9, "Microsoft YaHei");
   VBLabel(g_vbPfx+"_ACD",   cx, 264, "", C'180,200,220',  9, "Microsoft YaHei");

   //══ 二、同层对账台(Y=292 与左栏分区起点对齐) ══
   int cy = 292;
   VBLabel(g_vbPfx+"_H", cx, cy, "▌虚拟系统 ‖ 真实系统 · 同层对账台", clrGold, fs+3, "Microsoft YaHei");
   cy += fs + 16;
   for(int i=0; i<VB_SUM_ROWS; i++)
     {
      VBLabel(g_vbPfx+"_S"+IntegerToString(i), cx, cy, "", C'170,180,190', fs+1, "Microsoft YaHei");
      cy += fs + 9;
     }
   cy += 6;
   string rowFont = g_vbFont;
   VBLabel3("_CH", cx, cy, rfs, rowFont, C'120,190,255');
   cy += rfs + 8;

   int rowH = rfs + 5;
   int rows = (rowH > 0 ? ((y + h - 14) - cy) / rowH : 0);
   if(rows > VB_BOARD_ROWS) rows = VB_BOARD_ROWS;
   if(rows < 0) rows = 0;
   for(int i=0; i<rows; i++)
      VBLabel3("_R"+IntegerToString(i), cx, cy + i*rowH, rfs, rowFont, C'190,195,200');
   g_vbRows = rows;
   ChartRedraw();
  }

//==================== 左栏刷新 ====================
void UpdatePanelAll()
  {
   if(g_fd.inTester && !g_fd.visualMode) return;
   if(g_panel == NULL) { VomBoardUpdate(); return; }

   uint now = GetTickCount();
   if(now - g_lastStatTick >= 3000)
     {
      g_lastStatTick = now;
      g_panel.UpdateOrderStatistics(g_panel.GetStartTime());
     }

   double px = (g_fd.rType==UI_OP_SELL) ? UiAsk() : UiBid();
   double awayTP = (g_fd.redLine   > 0.0 && g_fd.rCnt>0 && g_fd.pt>0) ? MathAbs(px-g_fd.redLine)/g_fd.pt   : 0.0;
   double awaySL = (g_fd.blackLine > 0.0 && g_fd.rCnt>0 && g_fd.pt>0) ? MathAbs(px-g_fd.blackLine)/g_fd.pt : 0.0;

   //--- 顶部: 止损 / 止盈 / 加仓规则 / 周五避险+遥控
   string blkTxt;
   if(g_fd.slUSD <= 0.0)         blkTxt = "未启用(整篮止损关)";
   else if(g_fd.rCnt <= 0)       blkTxt = (g_fd.vomOn && g_fd.vCount>0 ? "待命(仅虚拟篮·无真实敞口)" : "待命(空仓)");
   else if(g_fd.blackLine > 0.0) blkTxt = StringFormat("%s  (距 %.0f点)", DoubleToString(g_fd.blackLine,_Digits), awaySL);
   else                          blkTxt = "价位不可达(手数过小, 亏损到不了止损额)";
   g_panel.SetLine("_GS", StringFormat("整篮止损线: %s | 止损额 -$%.0f | %s",
                   blkTxt, g_fd.slUSD, (g_fd.serverOn ? "服务器SL托管" : "EA市价执行")),
                   (g_fd.slUSD <= 0.0 ? clrTomato : clrOrange));
   g_panel.SetLine("_TRAIL", StringFormat("整篮止盈线: %s  (距 %.0f点 / 目标$%.2f)  真实均价 %s",
                   UiPx(g_fd.redLine), awayTP, g_fd.tpUSD, (g_fd.rCnt>0 ? DoubleToString(g_fd.rAvg,_Digits) : "-")), clrGold);
   g_panel.SetLine("_RECY", g_fd.addRuleTxt, clrAqua);
   g_panel.SetLine("_CD", "◆ " + g_fd.guardTxt, C'180,200,220');

   //--- 分区
   int elapse = (g_fd.lastAddTime>0) ? (int)(TimeCurrent()-g_fd.lastAddTime) : 0;
   string t1 = StringFormat("[间隔 %s] %.0f点 | 距上次下单%ds/节流%ds | 下次加仓价 %s",
                            g_fd.gapSrc, g_fd.gapPts, elapse, g_fd.throttleSec, UiPx(g_fd.nextAddPx));
   g_panel.SetLine("_T2_1", (g_fd.permitTxt=="" ? "待命" : g_fd.permitTxt),
                   (StringFind(g_fd.permitTxt,"放行")>=0 ? C'120,180,255' : clrGold));
   g_panel.SetLine("_T2_2", (g_fd.blockTxt=="" ? "" : "最近拦截: " + g_fd.blockTxt) + (g_fd.diagTxt=="" ? "" : " | " + g_fd.diagTxt),
                   (g_fd.blockTxt=="" ? C'100,160,235' : clrGold));
   g_panel.SetLine("_T3_1", g_fd.exitTxt1, C'160,190,220');
   g_panel.SetLine("_T3_2", g_fd.exitTxt2, C'160,170,180');
   g_panel.SetLine("_BULL_1", g_fd.spreadTxt, C'160,170,180');
   g_panel.SetLine("_BULL_2", g_fd.symTxt, C'160,170,180');

   g_panel.SetLine("_BEAR_1", StringFormat("%s多%d 空%d 总手%.2f 均价%s 最后单%.2f手@%s%s",
                   (g_fd.vomOn?"[决策面·虚拟] ":""),
                   g_fd.buyCnt, g_fd.sellCnt, g_fd.totLot,
                   (g_fd.cnt>0?DoubleToString(g_fd.avg,_Digits):"-"), g_fd.lastLot,
                   (g_fd.cnt>0?DoubleToString(g_fd.lastOpen,_Digits):"-"),
                   (g_fd.vomOn?StringFormat("  ‖ [执行面·真实] %d单 总手%.2f 均价%s",
                                          g_fd.rCnt, g_fd.rTotLot, (g_fd.rCnt>0?DoubleToString(g_fd.rAvg,_Digits):"-")):"")),
                   ((g_fd.mixed||g_fd.rMixed) ? clrTomato : C'160,170,180'));
   g_panel.SetLine("_BEAR_2", StringFormat("下一单 %.2f手(第%d层/封顶%d) | 预付款 $%.2f | 最大浮亏 -$%.2f",
                   g_fd.nextLot, g_fd.cnt+1, g_fd.maxLayers, g_fd.basketMargin, g_fd.maxDD), C'160,170,180');

   g_panel.SetLine("_FINAL_1", g_fd.finalTxt1,
                   ((g_fd.mixed||g_fd.rMixed||g_fd.halted) ? clrTomato : ((g_fd.paused||g_fd.closing) ? clrGold : clrLime)));
   g_panel.SetLine("_FINAL_2", g_fd.finalTxt2, C'190,190,190');

   if(g_fd.vomOn)
     {
      color vc = (g_fd.vHandoverCount>0) ? clrLime : (((g_fd.handoverLayer-g_fd.vCount)<=3) ? clrGold : C'150,190,240');
      g_panel.SetLine("_TRD_1", StringFormat("虚拟账本 第%d/%d层 %s 总手%.2f 均价%s 浮动%s%.2f | 闸门%d ⇒ 真实应有%d张/实有%d张 %s | 联动 %s",
                      g_fd.vCount, g_fd.maxLayers,
                      (g_fd.vDir==1?"多":(g_fd.vDir==-1?"空":(g_fd.vDir==2?"混合":"空仓"))),
                      g_fd.vVolume, UiPx(g_fd.vAvgPrice), (g_fd.vFloat>=0?"+$":"-$"), MathAbs(g_fd.vFloat),
                      g_fd.handoverLayer, g_fd.realWant, g_fd.rCnt,
                      (g_fd.realWant > g_fd.rCnt ? "待补+" : "已同步√"), g_fd.linkName), vc);
      g_panel.SetLine("_TRD_2", StringFormat("真实篮 %d单 %s 总手%.2f 浮动%s%.2f | 虚拟第%d篮 已完成%d篮 累计影子%s%.2f 最深%d层 切换%d次 真开%d笔%s",
                      g_fd.rCnt, DirOfType(g_fd.rType), g_fd.rTotLot, (g_fd.rPL>=0?"+$":"-$"), MathAbs(g_fd.rPL),
                      g_fd.vBasketSeq, g_fd.vClosedBaskets, (g_fd.vClosedPL>=0?"+$":"-$"), MathAbs(g_fd.vClosedPL),
                      g_fd.vMaxLayerEver, g_fd.vHandoverCount, g_fd.vRealOpened,
                      (g_fd.vBlockReason==""?"":" | 阻断:"+g_fd.vBlockReason)),
                      (g_fd.rMixed ? clrTomato : C'170,180,190'));
     }
   else
     {
      g_panel.SetLine("_TRD_1", "虚拟接管 OFF —— 全部下单直发券商(与 V1.3 逐笔一致)", C'140,150,160');
      g_panel.SetLine("_TRD_2", StringFormat("打开【虚拟接管启用】: 虚拟马丁到第%d层才下真实单, 右侧对账台逐层对照", g_fd.handoverLayer), C'140,150,160');
     }

   string trd = (g_fd.rCnt>0)
                ? StringFormat("%s真实篮 %d单 浮动%.2f 距止盈线%.0f点", DirOfType(g_fd.rType), g_fd.rCnt, g_fd.rPL, awayTP)
                : (g_fd.vomOn && g_fd.vCount>0
                   ? StringFormat("影子中 · 虚拟第%d层 浮动%.2f 距切换%d层", g_fd.vCount, g_fd.vFloat, g_fd.layersToGo)
                   : "HOLD · 等待开首单");
   g_panel.SetSignalInfo(g_fd.sigSrc, g_fd.entryTxt, t1, trd);

   string riskMode = (g_fd.serverOn ? "服务器TP/SL" : "EA执行");
   string scanSt   = StringFormat("间隔 %.0f点 | 节流 %ds | 层 %d/%d", g_fd.gapPts, g_fd.throttleSec, g_fd.cnt, g_fd.maxLayers);
   g_panel.UpdatePanel(g_fd.rBuy, g_fd.rSell, 0, g_fd.rPL, g_fd.maxDD, (g_fd.mixed||g_fd.rMixed),
                       g_fd.blackLine, g_fd.redLine, g_fd.tpArmed, g_fd.slArmed,
                       scanSt, g_fd.lastAction, g_fd.paused, riskMode, g_fd.tfMin, g_fd.basketMargin);
   g_panel.SetLine("_MDD", StringFormat("【本EA】浮亏峰值(运行以来) -%.2f  @%s  ‖  当前浮动 %s%.2f  ‖  魔术号 %I64d",
                   g_fd.maxDD, (g_fd.maxDDTime > 0 ? TimeToString(g_fd.maxDDTime, TIME_DATE|TIME_MINUTES) : "尚未发生"),
                   (g_fd.rPL >= 0.0 ? "+" : ""), g_fd.rPL, g_fd.magic),
                   (g_fd.maxDD > 0.0 ? clrTomato : C'160,170,180'));
   g_panel.SetPauseButtonText(g_fd.paused);

   //--- [v2.7] 宿主覆写: 最后写入, 覆盖上面任何一行
   if(g_fd.altOn)
      for(int k = 0; k < g_fd.ovrN && k < 40; k++)
         if(g_fd.ovrKey[k] != "") g_panel.SetLine(g_fd.ovrKey[k], g_fd.ovrTxt[k], g_fd.ovrClr[k]);

   VomBoardUpdate();
   g_panel.ThrottledRedraw(false);
  }

//==================== 轮次 ====================
void RoundAdvance(string why)
  {
   if(!InpRoundColorOn) return;
   int old = g_roundNo;
   g_roundNo++;
   if(g_roundNo > 100000) g_roundNo = 1;
   g_roundStart = TimeCurrent();
   g_rndT[g_roundNo % 16] = g_roundStart;
   if(!g_fd.inTester) GlobalVariableSet(g_uiGV, (double)g_roundNo);
   RoundArrowsDelete();
   PrintFormat("【轮次推进】第%d轮(%s) → 第%d轮(%s) | %s", old, RoundName(old), g_roundNo, RoundName(g_roundNo), why);
   if(g_panel != NULL)
      g_panel.LogMessage(StringFormat("【轮次】进入第%d轮 · 颜色%s · %s", g_roundNo, RoundName(g_roundNo), why));
  }

int UiRoundOfTime(datetime t)
  {
   for(int r = g_roundNo; r >= 1 && r > g_roundNo - 16; r--)
     {
      datetime st = g_rndT[r % 16];
      if(st > 0 && t >= st) return(r);
     }
   return(g_roundNo > 16 ? g_roundNo - 16 : 1);
  }

void RoundArrowsSync()
  {
   if(!InpRoundColorOn || !InpRoundArrow) { RoundArrowsDelete(); return; }
   if(g_fd.inTester && !g_fd.visualMode) return;
   int n = ArraySize(g_fd.rlegs);
   int tot = ObjectsTotal(0, 0, OBJ_ARROW);
   for(int i=tot-1; i>=0; i--)
     {
      string nm = ObjectName(0, i, 0, OBJ_ARROW);
      if(StringFind(nm, g_objRdPfx) != 0) continue;
      long tk = StringToInteger(StringSubstr(nm, StringLen(g_objRdPfx)));
      bool alive = false;
      for(int k=0; k<n; k++) if(g_fd.rlegs[k].has && g_fd.rlegs[k].ticket == tk) { alive = true; break; }
      if(!alive) ObjectDelete(0, nm);
     }
   for(int i=0; i<n; i++)
     {
      if(!g_fd.rlegs[i].has) continue;
      long     tk = g_fd.rlegs[i].ticket;
      double   px = g_fd.rlegs[i].open;
      datetime tm = g_fd.rlegs[i].tm;
      bool     sl = (g_fd.rlegs[i].dir < 0);
      int      rd = g_fd.rlegs[i].round;
      string   nm = g_objRdPfx + IntegerToString(tk);
      if(ObjectFind(0, nm) < 0)
        {
         ObjectCreate(0, nm, OBJ_ARROW, 0, tm, px);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
         ObjectSetInteger(0, nm, OBJPROP_BACK,       false);
        }
      ObjectMove      (0, nm, 0, tm, px);
      ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, (sl ? 234 : 233));
      ObjectSetInteger(0, nm, OBJPROP_COLOR,     RoundColor(rd));
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,     2);
      ObjectSetString (0, nm, OBJPROP_TOOLTIP,
                       StringFormat("第%d轮(%s) · %s %.2f手 @%s · #%I64d", rd, RoundName(rd), (sl?"空":"多"),
                                    g_fd.rlegs[i].lot, DoubleToString(px,_Digits), tk));
     }
  }

//==================== 同层对账台刷新 ====================
void VomBoardUpdate()
  {
   if(!VB_BOARD_ON) return;
   if(g_fd.inTester && !g_fd.visualMode) return;
   if(ObjectFind(0, g_vbPfx+"_BG") < 0) return;

   uint nowMs = GetTickCount();
   if(nowMs - g_vbLastTick < 300) return;
   g_vbLastTick = nowMs;

   RoundArrowsSync();
   VomAccountMirror();

   if(!g_fd.vomOn && g_fd.altOn)
     {
      VBSet("_H", g_fd.altBoardHead, clrGold);
      for(int i=0;i<VB_SUM_ROWS;i++) VBSet("_S"+IntegerToString(i), g_fd.altSum[i], g_fd.altSumClr[i]);
      VBSet3("_CH", g_fd.altColHead, "", "", C'120,190,255');
      int an = ArraySize(g_fd.altRows);
      for(int i=0;i<g_vbRows;i++)
        {
         if(i < an) VBSet3("_R"+IntegerToString(i), g_fd.altRows[i], "", "",
                           (i < ArraySize(g_fd.altRowClr) ? g_fd.altRowClr[i] : C'190,195,200'));
         else       VBSet3("_R"+IntegerToString(i), "", "", "", C'190,195,200');
        }
      ChartRedraw();
      return;
     }
   if(!g_fd.vomOn)
     {
      VBSet("_H", "▌虚拟系统 ‖ 真实系统 · 同层对账台 —— 虚拟接管 OFF", C'140,150,160');
      for(int i=0;i<VB_SUM_ROWS;i++) VBSet("_S"+IntegerToString(i), "", C'140,150,160');
      VBSet("_S0", "所有下单直发券商, 决策面 == 执行面, 只有一套系统, 无从对账。", C'150,160,170');
      VBSet("_S1", "要看双系统独立运行与同层对账, 请打开参数【虚拟接管启用】。", C'150,160,170');
      VBSet3("_CH", "", "", "", C'120,190,255');
      for(int i=0;i<g_vbRows;i++) VBSet3("_R"+IntegerToString(i), "", "", "", C'190,195,200');
      ChartRedraw();
      return;
     }

   int vn = ArraySize(g_fd.vlegs);
   int rn = ArraySize(g_fd.rlegs);
   int mirrored = 0;
   for(int i=0; i<vn && i<rn; i++) if(g_fd.vlegs[i].has && g_fd.rlegs[i].has) mirrored++;
   int dPhy = (g_fd.rCnt>0 && !g_fd.rMixed) ? (g_fd.rType==UI_OP_SELL ? -1 : 1) : 0;
   int dVir = (g_fd.vDir==1 || g_fd.vDir==-1) ? g_fd.vDir : 0;
   bool dirBad = (dPhy!=0 && dVir!=0 && dPhy!=dVir);

   VBSet("_H", StringFormat("▌虚拟系统 ‖ 真实系统 · 同层对账台 · ★第%d轮(%s)★ · 偏移跟随双系统 (VOM镜像%d/%d)%s",
               g_roundNo, RoundName(g_roundNo), mirrored, vn,
               (dirBad ? " ★方向不一致★" : (g_fd.rMixed ? " ★真实面多空混合★" : ""))),
         ((dirBad||g_fd.rMixed) ? clrTomato : (InpRoundColorOn ? RoundColor(g_roundNo) : clrGold)));

   VBSet("_S0", StringFormat("虚拟系统 第%d/%d层 %s 总手%.2f 均价%s 浮动%s$%.2f | 第%d篮 已完成%d篮",
                g_fd.vCount, g_fd.maxLayers,
                (g_fd.vDir==1?"多":(g_fd.vDir==-1?"空":(g_fd.vDir==2?"混合":"空仓"))),
                g_fd.vVolume, UiPx(g_fd.vAvgPrice), UiSgn(g_fd.vFloat), MathAbs(g_fd.vFloat),
                g_fd.vBasketSeq, g_fd.vClosedBaskets), C'200,200,130');
   VBSet("_S1", StringFormat("真实系统 %d单 %s 总手%.2f 均价%s 浮动%s$%.2f | 上限%d张",
                g_fd.rCnt, VBDirCN(dPhy), g_fd.rTotLot, (g_fd.rCnt>0?DoubleToString(g_fd.rAvg,_Digits):"-"),
                UiSgn(g_fd.rPL), MathAbs(g_fd.rPL), g_fd.realMaxCount), C'170,205,215');
   VBSet("_S2", StringFormat("方向契约 虚拟%s vs 真实%s → %s | 首单方向 %s",
                VBDirCN(dVir), VBDirCN(dPhy),
                (dPhy==0 ? "真实空篮·待跟随" : (dirBad ? "×不一致" : "√一致")), g_fd.entryTxt),
         (dirBad ? clrTomato : clrLime));
   double pxNow = (dPhy<0 || (dPhy==0 && dVir<0)) ? UiAsk() : UiBid();
   VBSet("_S3", StringFormat("红线对账 虚拟%s(距%.0f点) ‖ 真实%s(距%.0f点) | 目标 虚拟$%.2f 真实$%.2f",
                UiPx(g_fd.vRedLine), (g_fd.vRedLine>0.0 && g_fd.pt>0.0 ? MathAbs(pxNow-g_fd.vRedLine)/g_fd.pt : 0.0),
                UiPx(g_fd.redLine),  (g_fd.redLine>0.0  && g_fd.pt>0.0 ? MathAbs(pxNow-g_fd.redLine)/g_fd.pt  : 0.0),
                g_fd.vTPUSD, g_fd.tpUSD), C'230,170,170');
   VBSet("_S4", StringFormat("黑线对账 虚拟%s ‖ 真实%s | 止损额 虚拟$%.0f 真实$%.0f | 服务器TP/SL %s",
                UiPx(g_fd.vBlackLine), UiPx(g_fd.blackLine), g_fd.vSLUSD, g_fd.slUSD, (g_fd.serverOn?"ON":"OFF")),
         C'160,170,180');
   VBSet("_S5", StringFormat("手数契约 虚拟下一单%.2f手(第%d层) ‖ 真实手数=%s",
                g_fd.nextLot, g_fd.cnt+1, g_fd.lotModeName), clrLime);
   VBSet("_S6", StringFormat("偏移跟随 闸门%d(偏移%d) ⇒ 应有%d/实有%d张 %s | 跟随%s 上限%d | 阻断: %s",
                g_fd.handoverLayer, (g_fd.handoverLayer>0?g_fd.handoverLayer-1:0),
                g_fd.realWant, g_fd.rCnt,
                (g_fd.realWant > g_fd.rCnt ? "待补+" : (g_fd.realWant < g_fd.rCnt ? "超前(虚拟已退)" : "已同步√")),
                (g_fd.handoverMode==0 ? "只开一张" : "每层跟"), g_fd.realMaxCount,
                (g_fd.vBlockReason=="" ? "无" : g_fd.vBlockReason)),
         (g_fd.vBlockReason=="" ? C'170,200,190' : clrGold));
   VBSet("_S7", StringFormat("解耦 平仓联动=%s | 切换%d次 真开%d笔 | 虚拟胜%d 负%d | 累计影子%s%.2f",
                g_fd.linkName, g_fd.vHandoverCount, g_fd.vRealOpened, g_fd.vWinCnt, g_fd.vLossCnt,
                UiSgn(g_fd.vClosedPL), MathAbs(g_fd.vClosedPL)), C'160,170,180');

   { string hA,hB,hC; VBHeader3(hA,hB,hC); VBSet3("_CH", hA,hB,hC, C'120,190,255'); }

   int rowsN = (vn > rn ? vn : rn);
   int r = 0;
   for(int i=0; i<rowsN && r<g_vbRows; i++, r++)
     {
      bool vHas=false; int vDir=0; double vLot=0.0, vOpen=0.0, vPL=0.0, vExp=0.0; datetime vTm=0;
      if(i < vn && g_fd.vlegs[i].has)
        { vHas=true; vDir=g_fd.vlegs[i].dir; vLot=g_fd.vlegs[i].lot; vOpen=g_fd.vlegs[i].open; vTm=g_fd.vlegs[i].tm; vPL=g_fd.vlegs[i].pl; vExp=g_fd.vlegs[i].expLot; }
      bool rHas=false; int rDir=0; double rLot=0.0, rOpen=0.0, rPL=0.0, rExp=0.0; datetime rTm=0; long rT=0;
      if(i < rn && g_fd.rlegs[i].has)
        { rHas=true; rT=g_fd.rlegs[i].ticket; rDir=g_fd.rlegs[i].dir; rLot=g_fd.rlegs[i].lot; rOpen=g_fd.rlegs[i].open; rPL=g_fd.rlegs[i].pl; rTm=g_fd.rlegs[i].tm; rExp=g_fd.rlegs[i].expLot; }

      //--- 逐层核验: 虚拟手数 = 手数表第 i 层; 真实手数 = 真实手数模式应有值
      bool bad=false; string chk="";
      if(vHas && vExp>0 && MathAbs(vLot-vExp) > 1e-8) { chk += StringFormat("梯×V应%.2f", vExp); bad = true; }
      if(rHas && rExp>0 && MathAbs(rLot-rExp) > 1e-8) { chk += StringFormat("梯×R应%.2f", rExp); bad = true; }
      if(!bad) chk = StringFormat("梯√%.2f", (rHas ? rLot : vLot));
      if(vHas && rHas)   chk += (vDir==rDir ? " 同向" : " 反向");
      else if(vHas)      chk += (g_fd.handoverLayer>0 && i+1>=g_fd.handoverLayer ? " 真实未跟" : " 真实未到本层");
      else               chk += " 虚拟已退本层";

      int rdRow = 0; color rc;
      if(bad) rc = clrTomato;
      else if(InpRoundColorOn)
        {
         rdRow = (rHas ? g_fd.rlegs[i].round : g_roundNo);
         rc    = RoundColor(rdRow);
         chk  += StringFormat(" R%d", rdRow);
        }
      else rc = ((vHas && rHas) ? C'150,210,150' : C'165,170,178');

      string sA, sB, sC;
      VBRow3(IntegerToString(i+1),
             (vHas ? (vDir>0?"BUY":"SELL") : "-"), (vHas ? DoubleToString(vLot,2) : "-"),
             (vHas ? DoubleToString(vOpen,_Digits) : "-"), (vHas ? VBTime(vTm) : "-"), (vHas ? DoubleToString(vPL,2) : "-"),
             (rHas ? (rDir>0?"BUY":"SELL") : "-"), (rHas ? DoubleToString(rLot,2) : "-"),
             (rHas ? DoubleToString(rOpen,_Digits) : "-"), (rHas ? VBTime(rTm) : "-"), (rHas ? DoubleToString(rPL,2) : "-"),
             (rHas ? "#"+IntegerToString(rT) : "-"), chk, sA, sB, sC);
      VBSet3("_R"+IntegerToString(r), sA, sB, sC, rc);
     }
   for(; r<g_vbRows; r++) VBSet3("_R"+IntegerToString(r), "", "", "", C'190,195,200');
   ChartRedraw();
  }

//==================== 对外 API ====================
void UiInit(string pfx, long magic)
  {
   g_fd.inTester   = (MQLInfoInteger(MQL_TESTER) != 0 || MQLInfoInteger(MQL_OPTIMIZATION) != 0);
   g_fd.visualMode = (MQLInfoInteger(MQL_VISUAL_MODE) != 0);
   g_uiGV = "QGUI_RND_" + IntegerToString(magic) + "_" + Symbol();
   if(!g_fd.inTester && GlobalVariableCheck(g_uiGV)) g_roundNo = (int)GlobalVariableGet(g_uiGV);
   if(g_roundNo < 1) g_roundNo = 1;
   if(g_roundStart <= 0) g_roundStart = TimeCurrent();
   ArrayInitialize(g_rndT, 0);
   g_rndT[g_roundNo % 16] = g_roundStart;
   if(VB_HIDE_GRID) ChartSetInteger(0, CHART_SHOW_GRID, false);
   if(InpShowPanel)
     {
      g_panel = new CPanelEngine(pfx, InpPanelW, InpPanelH, 6, 40, magic);
      g_panel.SetSymbolFilter(Symbol());
      g_panel.SetVerbose(false);
      g_panel.CreatePanel();
     }
   VomBoardCreate();
  }
void UiSetTitle(string t)   { if(g_panel != NULL) g_panel.SetTitle(t); }
void UiSetLineStyle(color tpC,int tpW,ENUM_LINE_STYLE tpS,color slC,int slW,ENUM_LINE_STYLE slS)
  { g_lnTPColor=tpC; g_lnTPWidth=tpW; g_lnTPStyle=tpS; g_lnSLColor=slC; g_lnSLWidth=slW; g_lnSLStyle=slS; }
void UiLog(string t)        { if(g_panel != NULL) g_panel.LogMessage(t); }
bool UiHasPanel()           { return(g_panel != NULL); }
int  UiRoundNo()            { return(g_roundNo); }
void UiRelabel()            { RelabelPanel(); }
void UiDeleteLines()        { DeleteLines(); RoundArrowsDelete(); }
void UiRoundAdvance(string why) { RoundAdvance(why); }
void UiRender()
  {
   if(g_fd.inTester && !g_fd.visualMode) return;
   RelabelPanel();
   DrawLines();
   UpdatePanelAll();
  }
void UiDeinit()
  {
   DeleteLines(); RoundArrowsDelete(); VomBoardDelete();
   if(g_panel != NULL) { g_panel.Cleanup(); delete g_panel; g_panel = NULL; }
   Comment("");
  }
string        UiRoundName()  { return(RoundName(g_roundNo)); }

//--- [v2.7] 宿主覆写通道 API
void UiAltEnable(const bool on)                    { g_fd.altOn = on; }
void UiAltTitle(const string t)                    { g_fd.altTitle = t; }
void UiAltSection(const int k, const string t)     { if(k >= 0 && k < 9) g_fd.altSec[k] = t; }
void UiOverrideClear()                             { g_fd.ovrN = 0; }
void UiOverride(const string key, const string txt, const color c)
  {
   for(int k = 0; k < g_fd.ovrN; k++)
      if(g_fd.ovrKey[k] == key) { g_fd.ovrTxt[k] = txt; g_fd.ovrClr[k] = c; return; }
   if(g_fd.ovrN >= 40) return;
   g_fd.ovrKey[g_fd.ovrN] = key; g_fd.ovrTxt[g_fd.ovrN] = txt; g_fd.ovrClr[g_fd.ovrN] = c; g_fd.ovrN++;
  }
void UiAltMirror(const int k, const string t, const color c) { if(k >= 0 && k < 13) { g_fd.altMirror[k] = t; g_fd.altMirrorClr[k] = c; } }
void UiAltBoardHead(const string t)                { g_fd.altBoardHead = t; }
void UiAltSum(const int k, const string t, const color c)    { if(k >= 0 && k < VB_SUM_ROWS) { g_fd.altSum[k] = t; g_fd.altSumClr[k] = c; } }
void UiAltColHead(const string t)                  { g_fd.altColHead = t; }
void UiAltRows(const int n)                        { ArrayResize(g_fd.altRows, (n > 0 ? n : 0)); ArrayResize(g_fd.altRowClr, (n > 0 ? n : 0)); }
void UiAltRow(const int k, const string t, const color c)
  { if(k >= 0 && k < ArraySize(g_fd.altRows)) { g_fd.altRows[k] = t; g_fd.altRowClr[k] = c; } }
CPanelEngine *UiPanel()      { return(g_panel); }

#endif // __UI_PANEL_RENDER_MT5_V27_MQH__
//+------------------------------------------------------------------+
