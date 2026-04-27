using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using YukkuriMovieMaker.Commons;
using YukkuriMovieMaker.Controls;
using YukkuriMovieMaker.Exo;
using YukkuriMovieMaker.Player.Video;
using YukkuriMovieMaker.Plugin.Effects;

namespace DistortChroma
{
    [VideoEffect("ディストートクロマ", ["加工"], ["distort", "chroma", "歪み", "色収差", "色ズレ", "ブラー"])]
    internal class DistortChromaEffect : VideoEffectBase
    {
        public override string Label => "ディストートクロマ";

        [Display(GroupName = "基本", Name = "歪み強度", Description = "エフェクトの強さ（ピクセル単位）を指定します。")]
        [AnimationSlider("F1", "px", -100, 100)]
        public Animation Amount { get; } = new Animation(10f, -5000, 5000);

        [Display(GroupName = "基本", Name = "滑らかさ", Description = "歪みの滑らかさ（ブラー強度）です。")]
        [AnimationSlider("F1", "px", 0, 10)]
        public Animation Blur { get; } = new Animation(3f, 0, 100);

        [Display(GroupName = "基本", Name = "品質", Description = "色を分ける段階数です。高いほど滑らかになります。")]
        [AnimationSlider("F0", "段", 3, 32)]
        public Animation Steps { get; } = new Animation(16, 3, 64);

        [Display(GroupName = "基本", Name = "角度", Description = "歪みの回転角度です。")]
        [AnimationSlider("F1", "度", -360, 360)]
        public Animation Angle { get; } = new Animation(0f, -360, 360);

        public override IEnumerable<string> CreateExoVideoFilters(int keyFrameIndex, ExoOutputDescription exoOutputDescription) => [];

        public override IVideoEffectProcessor CreateVideoEffect(IGraphicsDevicesAndContext devices)
        {
            return new DistortChromaEffectProcessor(devices, this);
        }

        protected override IEnumerable<IAnimatable> GetAnimatables() => [Amount, Blur, Steps, Angle];
    }
}