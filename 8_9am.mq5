#property copyright "Estrategia Multi-Activo Guatemala"
#property version   "3.00"
#include <Trade\Trade.mqh>
CTrade trade;

//--- FILTROS DE DÍAS ACTIVOS ---
input bool     Operar_Lunes       = true;
input bool     Operar_Martes      = false;
input bool     Operar_Miercoles   = true;
input bool     Operar_Jueves      = false;
input bool     Operar_Viernes     = true;

//--- LOTAJE POR DÍA ---
input double   Lote_Lunes         = 0.01;
input double   Lote_Martes        = 0.01;
input double   Lote_Miercoles     = 0.01;
input double   Lote_Jueves        = 0.01;
input double   Lote_Viernes       = 0.01;

//--- TAKE PROFIT POR DÍA (USD DE RECORRIDO EN EL PRECIO DEL ACTIVO) ---
input double   TP_Lunes           = 15.0;    // Ej: 15.0 para Oro ($15 mov) o 100.0 para BTC
input double   TP_Martes          = 250.0;   // Ej: 250.0 para BTC
input double   TP_Miercoles       = 15.0;    // Ej: 15.0 para Oro
input double   TP_Jueves          = 500.0;   // Ej: 300.0 para BTC
input double   TP_Viernes         = 15.0;    // Ej: 15.0 para Oro

//--- GESTIÓN DE RIESGO Y HORARIO ---
input double   SL_Maximo_USD      = 100.0;   // Tope máximo de SL en recorrido de precio (Ej: 20.0 Oro / 500.0 BTC)
input int      Offset_Servidor_GT = 6;       // Servidor Exness (UTC+0) menos Guatemala (UTC-6) = 6
input bool     Cerrar_Fin_Dia     = true;    // Cerrar operaciones abiertas al final del día GT
input ulong    MagicNumber        = 20260809;// Cambiar si usas 2 gráficos a la vez (ej: 202601 Oro, 202602 BTC)

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

bool DiaActivo(int dia_sem)
{
   if(dia_sem == 1) return Operar_Lunes;
   if(dia_sem == 2) return Operar_Martes;
   if(dia_sem == 3) return Operar_Miercoles;
   if(dia_sem == 4) return Operar_Jueves;
   if(dia_sem == 5) return Operar_Viernes;
   return false;
}

double ObtenerLoteDia(int dia_sem)
{
   double vol_raw = Lote_Lunes;
   if(dia_sem == 2)      vol_raw = Lote_Martes;
   else if(dia_sem == 3) vol_raw = Lote_Miercoles;
   else if(dia_sem == 4) vol_raw = Lote_Jueves;
   else if(dia_sem == 5) vol_raw = Lote_Viernes;

   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   double vol = MathFloor(vol_raw / vol_step) * vol_step;
   if(vol < vol_min) vol = vol_min;
   if(vol > vol_max) vol = vol_max;
   return NormalizeDouble(vol, 2);
}

double ObtenerTPDia(int dia_sem)
{
   if(dia_sem == 2) return TP_Martes;
   if(dia_sem == 3) return TP_Miercoles;
   if(dia_sem == 4) return TP_Jueves;
   if(dia_sem == 5) return TP_Viernes;
   return TP_Lunes;
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

   if(!DiaActivo(dt_gt.day_of_week)) return;

   datetime tiempo_vela_actual = iTime(_Symbol, PERIOD_M15, 0);
   if(tiempo_vela_actual == ultima_vela) return;
   ultima_vela = tiempo_vela_actual;

   datetime tiempo_vela_cerrada_gt = iTime(_Symbol, PERIOD_M15, 1) - (Offset_Servidor_GT * 3600);
   MqlDateTime dt_vela;
   TimeToStruct(tiempo_vela_cerrada_gt, dt_vela);

   if(!DiaActivo(dt_vela.day_of_week)) return;

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
      int digitos    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double vol     = ObtenerLoteDia(dt_vela.day_of_week);
      double tp_hoy  = ObtenerTPDia(dt_vela.day_of_week);

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

   Print("=== RESUMEN ", _Symbol, " | Ganados: ", total_ganados, " | Perdidos: ", total_perdidos, " | Peor Dia: ", peor, " (", max_p, ") ===");
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
