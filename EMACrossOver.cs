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
	public class EMACrossOver : Strategy
	{
		private EMA emaFast;
		private EMA emaSlow;
		private RSI rsi;

		protected override void OnStateChange()
		{
			if (State == State.SetDefaults)
			{
				Description	= "EMACrossOver";
				Name		= "EMACrossOver";
				Fast		= 10;
				Slow		= 200;
				TP			= 10;
				SL			= 20;
				RsiPeriod	= 14;
				RsiSmooth	= 3;
				RsiLower	= 30;
				RsiUpper	= 70;
				// This strategy has been designed to take advantage of performance gains in Strategy Analyzer optimizations
				// See the Help Guide for additional information
				IsInstantiatedOnEachOptimizationIteration = false;
			}
			else if (State == State.DataLoaded)
			{
				emaFast = EMA(Fast);
				emaSlow = EMA(Slow);
				rsi		= RSI(RsiPeriod, RsiSmooth);

				emaFast.Plots[0].Brush = Brushes.Goldenrod;
				emaSlow.Plots[0].Brush = Brushes.SeaGreen;

				AddChartIndicator(emaFast);
				AddChartIndicator(emaSlow);
				AddChartIndicator(rsi);

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

			// Long: EMA cross up and RSI not overbought. Short: EMA cross down and RSI not oversold.
			if (CrossAbove(emaFast, emaSlow, 1) && rsi[0] < RsiUpper)
				EnterLong();
			else if (CrossBelow(emaFast, emaSlow, 1) && rsi[0] > RsiLower)
				EnterShort();
		}

		#region Properties
		[Range(1, int.MaxValue), NinjaScriptProperty]
		[Display(ResourceType = typeof(Custom.Resource), Name = "Fast", GroupName = "NinjaScriptStrategyParameters", Order = 0)]
		public int Fast { get; set; }

		[Range(1, int.MaxValue), NinjaScriptProperty]
		[Display(ResourceType = typeof(Custom.Resource), Name = "Slow", GroupName = "NinjaScriptStrategyParameters", Order = 1)]
		public int Slow { get; set; }

		[Range(1, int.MaxValue), NinjaScriptProperty]
		[Display(Name = "TP (ticks)", GroupName = "NinjaScriptStrategyParameters", Order = 2)]
		public int TP { get; set; }

		[Range(1, int.MaxValue), NinjaScriptProperty]
		[Display(Name = "SL (ticks)", GroupName = "NinjaScriptStrategyParameters", Order = 3)]
		public int SL { get; set; }

		[Range(1, int.MaxValue), NinjaScriptProperty]
		[Display(Name = "RSI Period", GroupName = "NinjaScriptStrategyParameters", Order = 4)]
		public int RsiPeriod { get; set; }

		[Range(1, int.MaxValue), NinjaScriptProperty]
		[Display(Name = "RSI Smooth", GroupName = "NinjaScriptStrategyParameters", Order = 5)]
		public int RsiSmooth { get; set; }

		[Range(0, 100), NinjaScriptProperty]
		[Display(Name = "RSI Lower", GroupName = "NinjaScriptStrategyParameters", Order = 6)]
		public int RsiLower { get; set; }

		[Range(0, 100), NinjaScriptProperty]
		[Display(Name = "RSI Upper", GroupName = "NinjaScriptStrategyParameters", Order = 7)]
		public int RsiUpper { get; set; }
		#endregion
	}
}
