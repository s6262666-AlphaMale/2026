//+------------------------------------------------------------------+
//|                                     品种自适应模块_MT5_v1.1.mqh   |
//|  交易品种自适应：基础品种识别（去经纪商前后缀）+ 小数位自适应点值   |
//|  只做计算，不发单、不改单、不改宿主状态                           |
//+------------------------------------------------------------------+
//  v1.1（MT5 原生移植，算法与 v1.0 逐字一致）
//   · v1.0 文件名标 MT5，但内部使用 MQL4 的 Digits / Point 裸标识符，MQL5 编译不过；
//     本版改为 _Digits / _Point / SymbolInfo*，函数名与返回值完全不变。
//  一、基础品种识别（「小写字母」后缀自适应）
//      XAUUSDm / XAUUSDr / XAUUSDc / XAUUSD.r / XAUUSD_i / #XAUUSD / xauusd → XAUUSD
//      GOLDm / GOLD. / GOLD.pro → GOLD；EURUSD.pro → EURUSD；US30m → US30
//  二、小数位自适应（pip → 微点倍数）
//      模式 0（自适应，默认）：黄金类 1 pip 恒等于 0.01 美元；其他品种经典 5/3 位规则
//      模式 1（旧规则）：5 位或 3 位报价，或品种名恰为 GOLD / GOLD. / GOLDm → 10，其余 1
//  用法：OnInit 先调 SA_Init(模式)，之后 SA_PipMult()/SA_Base()/SA_Suffix()/SA_IsGold()/SA_Describe()
//+------------------------------------------------------------------+
#ifndef SA_MODULE_V11
#define SA_MODULE_V11

#define SA_MODE_ADAPT   0   // 自适应
#define SA_MODE_LEGACY  1   // 旧规则

string SA_name   = "";
string SA_base   = "";
string SA_suffix = "";
int    SA_mode   = SA_MODE_ADAPT;
int    SA_digits = -1;
int    SA_mult   = 1;
bool   SA_gold   = false;

bool SA_IsUpperAlnum(const ushort c) { return ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')); }
bool SA_IsAlnum(const ushort c)      { return (SA_IsUpperAlnum(c) || (c >= 'a' && c <= 'z')); }

//--- 基础品种名
string SA_BaseOf(const string name)
  {
   int n = StringLen(name), i = 0;
   while(i < n && !SA_IsAlnum(StringGetCharacter(name, i))) i++;
   int j = i;
   while(j < n && SA_IsUpperAlnum(StringGetCharacter(name, j))) j++;
   if(j - i >= 3) return(StringSubstr(name, i, j - i));
   string u = name;                                                     // 小写或混排名称：转大写后再取
   StringToUpper(u);
   j = i;
   while(j < n && SA_IsUpperAlnum(StringGetCharacter(u, j))) j++;
   if(j > i) return(StringSubstr(u, i, j - i));
   return(u);
  }

//--- 经纪商后缀（基础名之后的部分，如 m / r / c / .r / _i / _EX；无则为空）
string SA_SuffixOf(const string name)
  {
   string b = SA_BaseOf(name), u = name;
   StringToUpper(u);
   int p = StringFind(u, b);
   if(p < 0) return("");
   return(StringSubstr(name, p + StringLen(b)));
  }

//--- 黄金类：XAU 开头（XAUUSD/XAUEUR…）或 GOLD 开头
bool SA_IsGoldBase(const string base)
  {
   return(StringFind(base, "XAU") == 0 || StringFind(base, "GOLD") == 0);
  }

//--- pip → 微点倍数（纯函数）
int SA_PipMultFor(const string name, const int digits, const double point, const int mode)
  {
   if(mode == SA_MODE_LEGACY)
     {
      if(digits == 5 || digits == 3 || name == "GOLD" || name == "GOLD." || name == "GOLDm") return(10);
      return(1);
     }
   if(SA_IsGoldBase(SA_BaseOf(name)) && point > 0.0)
     {
      int m = (int)MathRound(0.01 / point);                            // 黄金：1 pip = 0.01 美元
      return((m < 1) ? 1 : m);
     }
   return((digits == 5 || digits == 3) ? 10 : 1);                      // 其他品种：5/3 位规则
  }

//--- 初始化（品种与小数位在 EA 生命周期内不变；切换品种时 EA 会重新初始化）
void SA_Init(const int mode)
  {
   SA_mode   = (mode == SA_MODE_LEGACY) ? SA_MODE_LEGACY : SA_MODE_ADAPT;
   SA_name   = _Symbol;
   SA_digits = _Digits;
   SA_base   = SA_BaseOf(SA_name);
   SA_suffix = SA_SuffixOf(SA_name);
   SA_gold   = SA_IsGoldBase(SA_base);
   SA_mult   = SA_PipMultFor(SA_name, _Digits, _Point, SA_mode);
  }

int SA_PipMult()
  {
   if(SA_name != _Symbol || SA_digits != _Digits) SA_Init(SA_mode);    // 防御：品种/小数位变化时自动重算
   return(SA_mult);
  }

double SA_Pip()      { return(SA_PipMult() * _Point); }                 // 1 pip 的价格距离
string SA_Base()     { return(SA_base); }
string SA_Suffix()   { return(SA_suffix); }
bool   SA_IsGold()   { return(SA_gold); }
int    SA_Mode()     { return(SA_mode); }

//--- 旧规则下的倍数（用于日志提示两者差异）
int SA_LegacyMult() { return(SA_PipMultFor(SA_name, SA_digits, _Point, SA_MODE_LEGACY)); }

string SA_Describe()
  {
   string s = SA_name + " → " + SA_base;
   if(StringLen(SA_suffix) > 0) s += "（后缀 " + SA_suffix + "）";
   s += " | " + (SA_gold ? "黄金类" : "非黄金") + " | " + IntegerToString(SA_digits) + " 位报价 | 1 pip = " +
        DoubleToString(SA_mult * _Point, SA_digits) + "（" + IntegerToString(SA_mult) + " 微点）| " +
        ((SA_mode == SA_MODE_LEGACY) ? "旧规则" : "自适应");
   return(s);
  }

#endif
//+------------------------------------------------------------------+
