#property copyright "Estrategia BTC Guatemala"
#property version   "2.00"
#include <Trade\Trade.mqh>
CTrade trade;

input double   Lote               = 0.01;
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
bool     operado_hoy = false;
int      esperando_confirmacion = 0, dia_actual_gt = -1, dia_semana_entrada = 0;
int      total_ganados = 0, total_perdidos = 0;
int      perdidas_dia[5] = {0, 0, 0, 0, 0};
datetime ultima_vela = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   return(INIT_SUCCEEDED);
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

   double open_1 = iOpen(_Symbol, PERIOD_M15, 1);
   double high_1 = iHigh(_Symbol, PERIOD_M15, 1);
   double low_1  = iLow(_Symbol, PERIOD_M15, 1);
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
            if(trade.Buy(Lote, _Symbol, ask, NormalizeDouble(sl, digitos), NormalizeDouble(ask + tp_hoy, digitos), "Compra Confirmada"))
            {
               operado_hoy = true;
               esperando_confirmacion = 0;
               dia_semana_entrada = dt_vela.day_of_week - 1;
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
            if(trade.Sell(Lote, _Symbol, bid, NormalizeDouble(sl, digitos), NormalizeDouble(bid - tp_hoy, digitos), "Venta Confirmada"))
            {
               operado_hoy = true;
               esperando_confirmacion = 0;
               dia_semana_entrada = dt_vela.day_of_week - 1;
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
            if(dia_semana_entrada >= 0 && dia_semana_entrada < 5) perdidas_dia[dia_semana_entrada]++;
         }
      }
   }
}

double OnTester()
{
   string nombres[5] = {"Lunes", "Martes", "Miercoles", "Jueves", "Viernes"};
   int max_p = -1;
   string peor_dia = "Ninguno";
   for(int i = 0; i < 5; i++)
   {
      if(perdidas_dia[i] > max_p) { max_p = perdidas_dia[i]; peor_dia = nombres[i]; }
   }
   Print("=== RESUMEN 2026 | Ganados: ", total_ganados, " | Perdidos: ", total_perdidos, " | Peor Dia: ", peor_dia, " (", max_p, ") ===");
   Print("Perdidas -> Lun:", perdidas_dia[0], " Mar:", perdidas_dia[1], " Mie:", perdidas_dia[2], " Jue:", perdidas_dia[3], " Vie:", perdidas_dia[4]);
   return (double)(total_ganados - total_perdidos);
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
