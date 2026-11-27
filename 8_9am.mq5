#property copyright "Estrategia Multi-Activo Guatemala"
#property version   "4.00"
#include <Trade\Trade.mqh>
CTrade trade;

//--- FILTROS DE DÍAS ACTIVOS ---
input bool     Operar_Lunes           = true;
input bool     Operar_Martes          = true;
input bool     Operar_Miercoles       = true;
input bool     Operar_Jueves          = true;
input bool     Operar_Viernes         = true;

//--- GESTIÓN DE LOTAJE AUTOMÁTICO (MÁXIMO SEGÚN BALANCE) ---
input bool     Usar_Lotaje_Maximo     = true;    // true = Calcula el lote máximo posible; false = Usa Lote_Fijo
input double   Porcentaje_Margen_Usar = 95.0;    // % del margen libre a utilizar (95% deja colchón para el spread)
input double   Lote_Fijo              = 0.01;    // Solo se usa si Usar_Lotaje_Maximo = false

//--- TAKE PROFIT POR DÍA (USD DE RECORRIDO EN EL PRECIO DEL ACTIVO) ---
input double   TP_Lunes               = 15.0;
input double   TP_Martes              = 250.0;
input double   TP_Miercoles           = 15.0;
input double   TP_Jueves              = 300.0;
input double   TP_Viernes             = 15.0;

//--- STOP LOSS MÁXIMO POR DÍA (USD DE RECORRIDO EN EL PRECIO DEL ACTIVO) ---
input double   SL_Max_Lunes           = 20.0;
input double   SL_Max_Martes          = 500.0;
input double   SL_Max_Miercoles       = 20.0;
input double   SL_Max_Jueves          = 500.0;
input double   SL_Max_Viernes         = 20.0;

//--- HORARIO Y CONTROL ---
input int      Offset_Servidor_GT     = 6;       // Servidor Exness (UTC+0) menos Guatemala (UTC-6) = 6
input bool     Cerrar_Fin_Dia         = true;    // Cerrar operaciones abiertas al final del día GT
input ulong    MagicNumber            = 20260809;

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

double CalcularLoteMaximo(ENUM_ORDER_TYPE tipo_orden, double precio_entrada)
{
   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(!Usar_Lotaje_Maximo)
   {
      double v = MathFloor(Lote_Fijo / vol_step) * vol_step;
      return NormalizeDouble(MathMax(vol_min, MathMin(vol_max, v)), 2);
   }

   double margen_1_lote = 0.0;
   if(!OrderCalcMargin(tipo_orden, _Symbol, 1.0, precio_entrada, margen_1_lote) || margen_1_lote <= 0.0)
      return vol_min;

   double margen_disponible = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * (Porcentaje_Margen_Usar / 100.0);
   double lotes_calculados  = margen_disponible / margen_1_lote;

   // Redondear hacia abajo al múltiplo permitido por el bróker
   double vol = MathFloor(lotes_calculados / vol_step) * vol_step;
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

double ObtenerSLMaxDia(int dia_sem)
{
   if(dia_sem == 2) return SL_Max_Martes;
   if(dia_sem == 3) return SL_Max_Miercoles;
   if(dia_sem == 4) return SL_Max_Jueves;
   if(dia_sem == 5) return SL_Max_Viernes;
   return SL_Max_Lunes;
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
      double tp_hoy  = ObtenerTPDia(dt_vela.day_of_week);
      double sl_max  = ObtenerSLMaxDia(dt_vela.day_of_week);

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
            double vol = CalcularLoteMaximo(ORDER_TYPE_BUY, ask);
            double sl  = ((ask - min_rango) > sl_max) ? (ask - sl_max) : min_rango;
            if(trade.Buy(vol, _Symbol, ask, NormalizeDouble(sl, digitos), NormalizeDouble(ask + tp_hoy, digitos), "Compra Max Lote"))
            {
               operado_hoy = true;
               esperando_confirmacion = 0;
               dia_semana_entrada = dt_vela.day_of_week;
            }
            else if(!primer_log)
            {
               Print("Error Buy (Vol=", vol, "): ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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
            double vol = CalcularLoteMaximo(ORDER_TYPE_SELL, bid);
            double sl  = ((max_rango - bid) > sl_max) ? (bid + sl_max) : max_rango;
            if(trade.Sell(vol, _Symbol, bid, NormalizeDouble(sl, digitos), NormalizeDouble(bid - tp_hoy, digitos), "Venta Max Lote"))
            {
               operado_hoy = true;
               esperando_confirmacion = 0;
               dia_semana_entrada = dt_vela.day_of_week;
            }
            else if(!primer_log)
            {
               Print("Error Sell (Vol=", vol, "): ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
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
