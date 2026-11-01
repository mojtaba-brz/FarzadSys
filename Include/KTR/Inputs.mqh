#ifndef KTR_INPUTS_MQH
#define KTR_INPUTS_MQH
input group "General"
input KTR_DIRECTION Trade_Direction=TRADE_BOTH;
input ulong Magic_Number=471001;
input uint Max_Deviation_Points=10;
input group "First Entry / Ichimoku (standard 9/26/52, displacement 26)"
input KTR_FIRST First_Entry_Method=FIRST_EITHER;
input bool Enable_Tenkan_SSA_Valley=true;
input bool Enable_Tenkan_SSA_Peak=true;
input bool Enable_Kijun_SSA_Valley=true;
input bool Enable_Kijun_SSA_Peak=true;
input int Shape_Window_Bars=7;
input int Shape_Max_Lag_Bars=2;
input double Shape_Min_Similarity=0.90;
input int Shape_Pivot_Left_Bars=2;
input int Shape_Pivot_Right_Bars=2;
input double Shape_Min_Amplitude_ATR=0.05;
input double Shape_Plateau_Tolerance=0.01; // fraction of one trading tick; fixed across historical replay
input group "Additional Entry"
input bool Enable_LowerTF_Entry=false;
input ENUM_TIMEFRAMES Lower_Entry_Timeframe=PERIOD_M5;
input bool Enable_Kijun_Pullback=false;
input bool Enable_Tenkan_Kijun_Cross=false;
input bool Enable_Flat_SSB_Bounce=false;
input bool Enable_Kijun_Rejection=false;
input int Additional_Entry_Cooldown_Main_Bars=1;
input double Kijun_Touch_ATR=0.15;
input double Kijun_Rejection_Min_WickBody=1.5;
input group "First Entry Confirmations (AND)"
input bool First_Confirm_Price_Kumo=false;
input bool First_Confirm_TK=false;
input bool First_Confirm_Flat_SSB=false;
input bool First_Confirm_Swing_SR=false;
input bool First_Confirm_Thickness=false;
input bool First_Confirm_HigherTF=false;
input bool First_Confirm_Chikou=false;
input group "Additional Entry Confirmations (AND)"
input bool Additional_Confirm_Price_Kumo=false;
input bool Additional_Confirm_TK=false;
input bool Additional_Confirm_Flat_SSB=false;
input bool Additional_Confirm_Swing_SR=false;
input bool Additional_Confirm_Thickness=false;
input bool Additional_Confirm_HigherTF=false;
input bool Additional_Confirm_Chikou=false;
input group "Support, resistance and confirmation thresholds"
input int Flat_SSB_Min_Bars=5;
input double Flat_SSB_Max_Variation_ATR=0.05;
input double Flat_SSB_Touch_ATR=0.15;
input int Flat_SSB_Max_Age_Bars=100;
input int SR_Min_Touches=2;
input int SR_Min_Touch_Separation=3;
input int SR_Lookback_Bars=300;
input double SR_Tolerance_ATR=0.15;
input double Cloud_Min_Thickness_ATR=0.1;
input ENUM_TIMEFRAMES Higher_Confirmation_Timeframe=PERIOD_H4;
input double Chikou_Clearance_ATR=0.05;
input group "Stop loss"
input KTR_STOP SL_Method=SL_FRACTAL;
input double Fractal_Min_Distance_ATR=0.5;
input int Fractal_SL_Buffer_Ticks=2;
input int ZigZag_Depth=12;
input double ZigZag_Deviation=5; // broker points, as in standard ZigZag
input int ZigZag_Backstep=3;
input int ZigZag_SL_Buffer_Ticks=2;
input int Fixed_SL_Distance_Ticks=200;
input int ATR_Period=14;
input ENUM_TIMEFRAMES ATR_Timeframe=PERIOD_CURRENT;
input int Stop_History_Bars=1000;
input group "Risk"
input double First_Entry_Risk_Percent=2;
input double Max_Daily_Risk_Percent=5;
input KTR_RISK Additional_Risk_Method=ADD_RISK_FIXED_REDUCTION;
input double Additional_Risk_Reduction_Percent=20;
input int Trend_End_Horizon_Bars=10;
input int Trend_End_Min_Samples=50;
input int Trend_End_History_Bars=10000;
input double Commission_Reserve_Per_Lot=0; // account currency, round trip; max with observed broker charges
input group "Prop monitor / bounded historical reconstruction"
input bool Show_Prop_Monitor=true;
input ENUM_BASE_CORNER Monitor_Corner=CORNER_LEFT_UPPER;
input int Monitor_X=15;
input int Monitor_Y=20;
input int Monitor_Font_Size=10;
input color Monitor_Text_Color=clrWhite;
input color Monitor_Background_Color=clrBlack;
input double Initial_Deposit_Override=0;
input int Equity_History_Days=30;
input int Equity_Sample_Seconds=300;
input int Equity_Samples_Per_Timer=2;
input int Equity_Max_Samples=10000;
input int Broker_History_Refresh_Seconds=30;
#endif
