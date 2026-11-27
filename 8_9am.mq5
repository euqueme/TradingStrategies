#property copyright "Estrategia Multi-Activo Guatemala"
#property version   "4.30"
#include <Trade\Trade.mqh>
CTrade trade;

input bool   Operar_Lunes = true, Operar_Martes = true, Operar_Miercoles = true, Operar_Jueves = true, Operar_Viernes = true;
input bool   Usar_Lotaje_Maximo = true;
input double Porcentaje_Margen_Usar = 95.0, Lote_Fijo = 0.01;
input double TP_Lunes = 15.0, TP_Martes = 250.0, TP_Miercoles = 15.0, TP_Jueves = 300.0, TP_Viernes = 15.0;
input double SL_Max_Lunes = 20.0, SL_Max_Martes = 500.0, SL_Max_Miercoles = 20.0, SL_Max_Jueves = 500.0, SL_Max_Viernes = 20.0;
input int    Offset_Servidor_GT = 6;
input bool   Cerrar_Fin_Dia = true;
input ulong  MagicNumber = 20260809;

double max_rango = 0.0, min_rango = 0.0;
bool operado_hoy = false, primer_log = false;
int esperando_confirmacion = 0, dia_actual_gt = -1, dia_semana_entrada = 0, total_ganados = 0, total_perdidos = 0;
int p_lun = 0, p_mar = 0, p_mie = 0, p_jue = 0, p_vie = 0;
datetime ultima_vela = 0;

int OnInit() { trade.SetExpertMagicNumber(MagicNumber); trade.SetTypeFillingBySymbol(_Symbol); return(INIT_SUCCEEDED); }

bool DiaActivo(int d) { return (d==1 && Operar_Lunes) || (d==2 && Operar_Martes) || (d==3 && Operar_Miercoles) || (d==4 && Operar_Jueves) || (d==5 && Operar_Viernes); }
double ObtenerTPDia(int d) { return (d==2)?TP_Martes:(d==3)?TP_Miercoles:(d==4)?TP_Jueves:(d==5)?TP_Viernes:TP_Lunes; }
double ObtenerSLMaxDia(int d) { return (d==2)?SL_Max_Martes:(d==3)?SL_Max_Miercoles:(d==4)?SL_Max_Jueves:(d==5)?SL_Max_Viernes:SL_Max_Lunes; }

double CalcularLoteMaximo(ENUM_ORDER_TYPE tipo, double precio)
{
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(!Usar_Lotaje_Maximo) return NormalizeDouble(MathMax(vmin, MathMin(vmax, MathFloor(Lote_Fijo / vstep) * vstep)), 2);
   double m1 = 0.0;
   if(!OrderCalcMargin(tipo, _Symbol, 1.0, precio, m1) || m1 <= 0.0) return vmin;
   double vol = MathFloor((AccountInfoDouble(ACCOUNT_MARGIN_FREE) * (Porcentaje_Margen_Usar / 100.0) / m1) / vstep) * vstep;
   return NormalizeDouble(MathMax(vmin, MathMin(vmax, vol)), 2);
}

void EjecutarCompra(int d, double tp_h, double sl_m, int dig)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), vol = CalcularLoteMaximo(ORDER_TYPE_BUY, ask);
   double sl = ((ask - min_rango) > sl_m) ? (ask - sl_m) : min_rango;
   if(trade.Buy(vol, _Symbol, ask, NormalizeDouble(sl, dig), NormalizeDouble(ask + tp_h, dig), "Compra Cuerpo > Max"))
   { operado_hoy = true; esperando_confirmacion = 0; dia_semana_entrada = d; }
   else if(!primer_log) { Print("Error Buy: ", trade.ResultRetcodeDescription()); primer_log = true; }
}

void EjecutarVenta(int d, double tp_h, double sl_m, int dig)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), vol = CalcularLoteMaximo(ORDER_TYPE_SELL, bid);
   double sl = ((max_rango - bid) > sl_m) ? (bid + sl_m) : max_rango;
   if(trade.Sell(vol, _Symbol, bid, NormalizeDouble(sl, dig), NormalizeDouble(bid - tp_h, dig), "Venta Cuerpo < Min"))
   { operado_hoy = true; esperando_confirmacion = 0; dia_semana_entrada = d; }
   else if(!primer_log) { Print("Error Sell: ", trade.ResultRetcodeDescription()); primer_log = true; }
}

void OnTick()
{
   MqlDateTime dt_gt, dt_vela;
   TimeToStruct(TimeCurrent() - (Offset_Servidor_GT * 3600), dt_gt);
   if(dt_gt.day_of_year != dia_actual_gt)
   {
      if(Cerrar_Fin_Dia) CerrarTodasLasPosiciones();
      dia_actual_gt = dt_gt.day_of_year; max_rango = 0.0; min_rango = 0.0; operado_hoy = false; esperando_confirmacion = 0;
   }
   if(!DiaActivo(dt_gt.day_of_week)) return;

   datetime t_act = iTime(_Symbol, PERIOD_M15, 0);
   if(t_act == ultima_vela) return;
   ultima_vela = t_act;

   TimeToStruct(iTime(_Symbol, PERIOD_M15, 1) - (Offset_Servidor_GT * 3600), dt_vela);
   if(!DiaActivo(dt_vela.day_of_week)) return;

   double o1 = iOpen(_Symbol, PERIOD_M15, 1), h1 = iHigh(_Symbol, PERIOD_M15, 1), l1 = iLow(_Symbol, PERIOD_M15, 1), c1 = iClose(_Symbol, PERIOD_M15, 1);
   if(dt_vela.hour == 8)
   {
      if(max_rango == 0.0 || h1 > max_rango) max_rango = h1;
      if(min_rango == 0.0 || l1 < min_rango) min_rango = l1;
      return;
   }

   if(dt_vela.hour >= 9 && !operado_hoy && max_rango > 0.0 && min_rango > 0.0 && !TienePosicionAbierta())
   {
      bool azul = (c1 > o1), roja = (c1 < o1);
      double cuerpo_sup = MathMax(o1, c1), cuerpo_inf = MathMin(o1, c1);
      bool parte_cuerpo_arriba = (cuerpo_sup > max_rango); // Parte del cuerpo supera la mecha maxima
      bool parte_cuerpo_abajo  = (cuerpo_inf < min_rango); // Parte del cuerpo debajo de la mecha minima

      int dig = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double tp_h = ObtenerTPDia(dt_vela.day_of_week), sl_m = ObtenerSLMaxDia(dt_vela.day_of_week);

      if(esperando_confirmacion == 0)
      {
         if(parte_cuerpo_arriba)
         {
            if(roja) EjecutarCompra(dt_vela.day_of_week, tp_h, sl_m, dig);
            else if(azul) esperando_confirmacion = 1;
         }
         else if(parte_cuerpo_abajo)
         {
            if(azul) EjecutarVenta(dt_vela.day_of_week, tp_h, sl_m, dig);
            else if(roja) esperando_confirmacion = -1;
         }
      }
      else if(esperando_confirmacion == 1)
      {
         if(c1 <= min_rango) { esperando_confirmacion = 0; operado_hoy = true; }
         else if(roja && parte_cuerpo_arriba) EjecutarCompra(dt_vela.day_of_week, tp_h, sl_m, dig);
      }
      else if(esperando_confirmacion == -1)
      {
         if(c1 >= max_rango) { esperando_confirmacion = 0; operado_hoy = true; }
         else if(azul && parte_cuerpo_abajo) EjecutarVenta(dt_vela.day_of_week, tp_h, sl_m, dig);
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
            if(dia_semana_entrada == 1) p_lun++; else if(dia_semana_entrada == 2) p_mar++; else if(dia_semana_entrada == 3) p_mie++; else if(dia_semana_entrada == 4) p_jue++; else if(dia_semana_entrada == 5) p_vie++;
         }
      }
   }
}

void OnDeinit(const int reason)
{
   string peor = "Lunes"; int max_p = p_lun;
   if(p_mar > max_p) { max_p = p_mar; peor = "Martes"; } if(p_mie > max_p) { max_p = p_mie; peor = "Miercoles"; } if(p_jue > max_p) { max_p = p_jue; peor = "Jueves"; } if(p_vie > max_p) { max_p = p_vie; peor = "Viernes"; }
   Print("=== RESUMEN ", _Symbol, " | Ganados: ", total_ganados, " | Perdidos: ", total_perdidos, " | Peor Dia: ", peor, " (", max_p, ") ===");
   Print("Perdidas -> Lun:", p_lun, " Mar:", p_mar, " Mie:", p_mie, " Jue:", p_jue, " Vie:", p_vie);
}

bool TienePosicionAbierta()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   { ulong t = PositionGetTicket(i); if(PositionSelectByTicket(t) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) return true; }
   return false;
}

void CerrarTodasLasPosiciones()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   { ulong t = PositionGetTicket(i); if(PositionSelectByTicket(t) && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber) trade.PositionClose(t); }
}
