// AB 20-09-2026
//
#region Using declarations
using System.ComponentModel.DataAnnotations;
using System.Windows.Media;
using NinjaTrader.Cbi;
using NinjaTrader.NinjaScript.Indicators;
#endregion

//This namespace holds strategies in this folder and is required. Do not change it.
namespace NinjaTrader.NinjaScript.Strategies
{
	public class SMACrossOver : Strategy
	{
		private SMA smaFast;
		private SMA smaSlow;

		protected override void OnStateChange()
		{
			if (State == State.SetDefaults)
			{
				Description	= "SMACrossOver";
				Name		= "SMACrossOver";
				Fast		= 10;
				Slow		= 200;
				TP		= 80;
				SL		= 15;
				// This strategy has been designed to take advantage of performance gains in Strategy Analyzer optimizations
				// See the Help Guide for additional information
				IsInstantiatedOnEachOptimizationIteration = false;
			}
			else if (State == State.DataLoaded)
			{
				smaFast = SMA(Fast);
				smaSlow = SMA(Slow);

				smaFast.Plots[0].Brush = Brushes.Goldenrod;
				smaSlow.Plots[0].Brush = Brushes.SeaGreen;

				AddChartIndicator(smaFast);
				AddChartIndicator(smaSlow);

				SetProfitTarget(CalculationMode.Ticks, TP);
				SetStopLoss(CalculationMode.Ticks, SL);
			}
		}

		protected override void OnBarUpdate()
		{
			if (CurrentBar < BarsRequiredToTrade)
				return;

			if (Position.MarketPosition != MarketPosition.Flat)
				return;

			if (CrossAbove(smaFast, smaSlow, 1))
				EnterLong();
			else if (CrossBelow(smaFast, smaSlow, 1))
				EnterShort();
		}

		#region Properties
		[Range(1, int.MaxValue), NinjaScriptProperty]
		// [Display(ResourceType = typeof(Custom.Resource), Name = "Fast", GroupName = "NinjaScriptStrategyParameters", Order = 0)]
		[Display(Name = "Fast (bars)", GroupName = "StrategyParameters", Order = 0)]
		public int Fast { get; set; }

		[Range(2, int.MaxValue), NinjaScriptProperty]
		//[Display(ResourceType = typeof(Custom.Resource), Name = "Slow", GroupName = "NinjaScriptStrategyParameters", Order = 1)]
		[Display(Name = "Slow (bars)", GroupName = "StrategyParameters", Order = 1)]
		public int Slow { get; set; }

		[Range(1, int.MaxValue), NinjaScriptProperty]
		[Display(Name = "TP (ticks)", GroupName = "StrategyParameters", Order = 2)]
		public int TP { get; set; }

		[Range(1, int.MaxValue), NinjaScriptProperty]
		[Display(Name = "SL (ticks)", GroupName = "StrategyParameters", Order = 3)]
		public int SL { get; set; }
		#endregion
	}
}
