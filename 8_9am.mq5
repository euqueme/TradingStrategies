#property copyright "Estrategia BTC Guatemala"
#property version   "2.20"
#include <Trade\Trade.mqh>
CTrade trade;

input double   Lote               = 0.04;    // Lote base (usar >= 0.04 para que aplique 75% y 50%)
input double   Pct_Miercoles      = 50.0;    // % de lote a operar los Miercoles
input double   Pct_Viernes        = 75.0;    // % de lote a operar los Viernes
input double   TP_Lunes           = 25.0;
input double   TP_Martes          = 250.0;
input double   TP_Miercoles       = 100.0;
input double   TP_Jueves          = 500.0;
input double   TP_Viernes         = 250.0;
input double   SL_Maximo_USD      = 800.0;
input int      Offset_Servidor_GT = 6;
input bool     Cerrar_Fin_Dia     = true;
input ulong    MagicNumber        = 20260809;

double   max_rango = 0.0, min_rango = 0.0;
bool     operado_hoy = false, primer_log = false;
int      esperando_confirmacion = 0, dia_actual_gt = -1, dia_semana_entrada = 0;
int      total_ganados = 0, total_perdidos = 0;
int      p_lun = 0, p_mar = 0, p_mie = 0, p_jue = 0, p_vie = 0;
datetime ultima_vela = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   return(INIT_SUCCEEDED);
}

double CalcularLoteDia(int dia_semana)
{
   double factor = 1.0;
   if(dia_semana == 3) factor = Pct_Miercoles / 100.0;      // Miercoles = 50%
   else if(dia_semana == 5) factor = Pct_Viernes / 100.0;   // Viernes = 75%

   double vol_raw  = Lote * factor;
   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double vol = MathFloor(vol_raw / vol_step) * vol_step;
   if(vol < vol_min) vol = vol_min;
   if(vol > vol_max) vol = vol_max;
   return NormalizeDouble(vol, 2);
}

void OnTick()
{
   datetime hora_gt_dt = TimeCurrent() - (Offset_Servidor_GT * 3600);
   MqlDateTime dt_gt;
   TimeToStruct(hora_gt_dt, dt_gt);

   if(dt_gt.day_of_year != dia_actual_gt)
   {
      if(Cerrar_Fin_Dia) CerrarTodasLasPosiciones();
      dia_actual_gt = dt_gt.day_of_year;
      max_rango = 0.0;
      min_rango = 0.0;
      operado_hoy = false;
      esperando_confirmacion = 0;
   }

   if(dt_gt.day_of_week < 1 || dt_gt.day_of_week > 5) return;

   datetime tiempo_vela_actual = iTime(_Symbol, PERIOD_M15, 0);
   if(tiempo_vela_actual == ultima_vela) return;
   ultima_vela = tiempo_vela_actual;

   datetime tiempo_vela_cerrada_gt = iTime(_Symbol, PERIOD_M15, 1) - (Offset_Servidor_GT * 3600);
   MqlDateTime dt_vela;
   TimeToStruct(tiempo_vela_cerrada_gt, dt_vela);

   double open_1  = iOpen(_Symbol, PERIOD_M15, 1);
   double high_1  = iHigh(_Symbol, PERIOD_M15, 1);
   double low_1   = iLow(_Symbol, PERIOD_M15, 1);
   double close_1 = iClose(_Symbol, PERIOD_M15, 1);

   if(dt_vela.hour == 8)
   {
      if(max_rango == 0.0 || high_1 > max_rango) max_rango = high_1;
      if(min_rango == 0.0 || low_1 < min_rango) min_rango = low_1;
      return;
   }

   if(dt_vela.hour >= 9 && !operado_hoy && max_rango > 0.0 && min_rango > 0.0 && !TienePosicionAbierta())
   {
      bool vela_azul = (close_1 > open_1);
      bool vela_roja = (close_1 < open_1);
      int digitos = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double vol = CalcularLoteDia(dt_vela.day_of_week);

      double tp_hoy = TP_Lunes;
      if(dt_vela.day_of_week == 2) tp_hoy = TP_Martes;
      else if(dt_vela.day_of_week == 3) tp_hoy = TP_Miercoles;
      else if(dt_vela.day_of_week == 4) tp_hoy = TP_Jueves;
      else if(dt_vela.day_of_week == 5) tp_hoy = TP_Viernes;

      if(esperando_confirmacion == 0)
      {
         if(close_1 > max_rango && vela_azul) esperando_confirmacion = 1;
         else if(close_1 < min_rango && vela_roja) esperando_confirmacion = -1;
      }
      else if(esperando_confirmacion == 1)
      {
         if(close_1 <= min_rango)
         {
            esperando_confirmacion = 0;
            operado_hoy = true;
         }
         else if(vela_roja)
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl = ((ask - min_rango) > SL_Maximo_USD) ? (ask - SL_Maximo_USD) : min_rango;
            if(trade.Buy(vol, _Symbol, ask, NormalizeDouble(sl, digitos), NormalizeDouble(ask + tp_hoy, digitos), "Compra Confirmada"))
            {
               operado_hoy = true;
               esperando_confirmacion = 0;
               dia_semana_entrada = dt_vela.day_of_week;
            }
            else if(!primer_log)
            {
               Print("Error Buy: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               primer_log = true;
            }
         }
      }
      else if(esperando_confirmacion == -1)
      {
         if(close_1 >= max_rango)
         {
            esperando_confirmacion = 0;
            operado_hoy = true;
         }
         else if(vela_azul)
         {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double sl = ((max_rango - bid) > SL_Maximo_USD) ? (bid + SL_Maximo_USD) : max_rango;
            if(trade.Sell(vol, _Symbol, bid, NormalizeDouble(sl, digitos), NormalizeDouble(bid - tp_hoy, digitos), "Venta Confirmada"))
            {
               operado_hoy = true;
               esperando_confirmacion = 0;
               dia_semana_entrada = dt_vela.day_of_week;
            }
            else if(!primer_log)
            {
               Print("Error Sell: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
               primer_log = true;
            }
         }
      }
   }
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
   {
      if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT && HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == MagicNumber)
      {
         if(HistoryDealGetDouble(trans.deal, DEAL_PROFIT) >= 0.0) total_ganados++;
         else
         {
            total_perdidos++;
            if(dia_semana_entrada == 1) p_lun++;
            else if(dia_semana_entrada == 2) p_mar++;
            else if(dia_semana_entrada == 3) p_mie++;
            else if(dia_semana_entrada == 4) p_jue++;
            else if(dia_semana_entrada == 5) p_vie++;
         }
      }
   }
}

void OnDeinit(const int reason)
{
   string peor = "Lunes";
   int max_p = p_lun;
   if(p_mar > max_p) { max_p = p_mar; peor = "Martes"; }
   if(p_mie > max_p) { max_p = p_mie; peor = "Miercoles"; }
   if(p_jue > max_p) { max_p = p_jue; peor = "Jueves"; }
   if(p_vie > max_p) { max_p = p_vie; peor = "Viernes"; }

   Print("=== RESUMEN 2026 | Ganados: ", total_ganados, " | Perdidos: ", total_perdidos, " | Peor Dia: ", peor, " (", max_p, ") ===");
   Print("Perdidas -> Lun:", p_lun, " Mar:", p_mar, " Mie:", p_mie, " Jue:", p_jue, " Vie:", p_vie);
}

bool TienePosicionAbierta()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

void CerrarTodasLasPosiciones()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         trade.PositionClose(ticket);
   }
}
