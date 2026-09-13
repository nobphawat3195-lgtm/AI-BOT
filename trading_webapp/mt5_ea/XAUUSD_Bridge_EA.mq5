//+------------------------------------------------------------------+
//|                                          XAUUSD_Bridge_EA.mq5    |
//|  Executes signals published by the FastAPI bridge.                |
//|                                                                   |
//|  SETUP (required once in MetaTrader 5):                           |
//|    Tools > Options > Expert Advisors                              |
//|      [x] Allow WebRequest for listed URL                          |
//|      add:  http://127.0.0.1:8000                                  |
//|                                                                   |
//|  The EA polls /api/ea/next-signal and opens at most one position  |
//|  per signal id. Risk sizing and all gating happen server-side;    |
//|  the EA re-checks lot bounds and stop distance before sending.    |
//+------------------------------------------------------------------+
#property copyright "XAUUSD Auto Trading"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

input string   InpApiBase      = "http://127.0.0.1:8000";  // Bridge base URL
input string   InpApiToken     = "change-me";              // X-API-Token
input int      InpPollSeconds  = 5;                        // Poll interval (seconds)
input ulong    InpMagic        = 990045;                   // Magic number
input int      InpSlippage     = 20;                       // Max deviation (points)
input bool     InpDryRun       = true;                     // true = log only, never trade
input double   InpMaxLot       = 1.0;                      // Hard local lot ceiling

CTrade   trade;
datetime g_last_poll   = 0;
string   g_last_signal = "";

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(InpDryRun)
      Print("[bridge] DRY RUN — signals will be logged, no orders sent.");
   else
      Print("[bridge] LIVE — this EA will place real orders on ", _Symbol);

   Print("[bridge] polling ", InpApiBase, " every ", InpPollSeconds, "s");
   EventSetTimer(MathMax(1, InpPollSeconds));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   PollForSignal();
}

//+------------------------------------------------------------------+
//| Minimal string-value extractor for the bridge's flat JSON.        |
//+------------------------------------------------------------------+
string JsonValue(const string json, const string key)
{
   string needle = "\"" + key + "\"";
   int k = StringFind(json, needle);
   if(k < 0)
      return("");

   int colon = StringFind(json, ":", k + StringLen(needle));
   if(colon < 0)
      return("");

   int i = colon + 1;
   int n = StringLen(json);
   while(i < n)  // skip whitespace
   {
      ushort c = StringGetCharacter(json, i);
      if(c != ' ' && c != '\t' && c != '\n' && c != '\r')
         break;
      i++;
   }
   if(i >= n)
      return("");

   if(StringGetCharacter(json, i) == '"')       // quoted string
   {
      int end = StringFind(json, "\"", i + 1);
      if(end < 0)
         return("");
      return(StringSubstr(json, i + 1, end - i - 1));
   }

   int end = i;                                  // bare number / literal
   while(end < n)
   {
      ushort c = StringGetCharacter(json, end);
      if(c == ',' || c == '}' || c == ']')
         break;
      end++;
   }
   string raw = StringSubstr(json, i, end - i);
   StringTrimLeft(raw);
   StringTrimRight(raw);
   return(raw);
}

//+------------------------------------------------------------------+
bool HttpGet(const string url, string &out_body)
{
   char   post[], result[];
   string headers = "X-API-Token: " + InpApiToken + "\r\n";
   string result_headers;

   ResetLastError();
   int status = WebRequest("GET", url, headers, 5000, post, result, result_headers);

   if(status == -1)
   {
      int err = GetLastError();
      if(err == 4060)
         Print("[bridge] ERROR 4060 — add ", InpApiBase,
               " to Tools > Options > Expert Advisors > Allow WebRequest");
      else
         Print("[bridge] WebRequest failed, error ", err);
      return(false);
   }
   if(status != 200)
   {
      Print("[bridge] HTTP ", status, " from bridge");
      return(false);
   }

   out_body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   return(true);
}

//+------------------------------------------------------------------+
void PollForSignal()
{
   string body;
   if(!HttpGet(InpApiBase + "/api/ea/next-signal", body))
      return;

   string id = JsonValue(body, "id");
   if(id == "" || id == "null")
      return;                     // nothing pending

   if(id == g_last_signal)
      return;                     // already handled

   string side   = JsonValue(body, "side");
   double volume = StringToDouble(JsonValue(body, "volume"));
   double sl     = StringToDouble(JsonValue(body, "stop_loss"));
   double tp     = StringToDouble(JsonValue(body, "take_profit"));
   string symbol = JsonValue(body, "symbol");

   if(symbol == "")
      symbol = _Symbol;

   g_last_signal = id;

   PrintFormat("[bridge] signal %s: %s %.2f lots sl=%.2f tp=%.2f",
               id, side, volume, sl, tp);

   if(InpDryRun)
   {
      Print("[bridge] dry run — not sending.");
      return;
   }
   Execute(symbol, side, volume, sl, tp);
}

//+------------------------------------------------------------------+
//| Local sanity checks, then send. The server already sized the      |
//| trade; these guards catch a misconfigured or spoofed bridge.      |
//+------------------------------------------------------------------+
void Execute(const string symbol, const string side, double volume,
             double sl, double tp)
{
   if(side != "BUY" && side != "SELL")
   {
      Print("[bridge] refusing unknown side: ", side);
      return;
   }

   double min_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(lot_step > 0)
      volume = MathRound(volume / lot_step) * lot_step;
   volume = MathMin(volume, MathMin(max_lot, InpMaxLot));

   if(volume < min_lot)
   {
      PrintFormat("[bridge] refusing volume %.4f, below broker minimum %.4f",
                  volume, min_lot);
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
   {
      Print("[bridge] no tick for ", symbol);
      return;
   }

   double price  = (side == "BUY") ? tick.ask : tick.bid;
   long   digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   long   stops  = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_d  = stops * point;

   sl = NormalizeDouble(sl, (int)digits);
   tp = NormalizeDouble(tp, (int)digits);

   // A stop inside the broker's freeze band is rejected server-side;
   // drop it rather than have the whole order bounce.
   if(sl > 0 && MathAbs(price - sl) < min_d)
   {
      PrintFormat("[bridge] SL %.2f too close to %.2f (min %.2f) — sending without SL",
                  sl, price, min_d);
      sl = 0;
   }
   if(tp > 0 && MathAbs(price - tp) < min_d)
   {
      PrintFormat("[bridge] TP %.2f too close — sending without TP", tp);
      tp = 0;
   }

   bool ok = (side == "BUY")
             ? trade.Buy(volume, symbol, 0.0, sl, tp, "bridge")
             : trade.Sell(volume, symbol, 0.0, sl, tp, "bridge");

   if(ok)
      PrintFormat("[bridge] %s %.2f %s OK, ticket %I64u",
                  side, volume, symbol, trade.ResultOrder());
   else
      PrintFormat("[bridge] order failed: retcode=%u %s",
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
}
//+------------------------------------------------------------------+
