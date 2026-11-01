#property strict
#property script_show_inputs
#include "../../Include/KTR/Core.mqh"
#include "../../Include/KTR/Recovery.mqh"
#include "CoreCases.mqh"
#include "RecoveryCases.mqh"
void OnStart() { KTRRunCoreCases(); KTRRunRecoveryCases(); }
