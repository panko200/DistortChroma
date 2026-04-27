using System;
using Vortice.Direct2D1;
using YukkuriMovieMaker.Commons;
using YukkuriMovieMaker.Player.Video;

namespace DistortChroma
{
    internal class DistortChromaEffectProcessor : IVideoEffectProcessor, IDisposable
    {
        private readonly DistortChromaEffect item;
        private readonly IGraphicsDevicesAndContext devices;
        private ID2D1Image? input;
        private DistortChromaCustomEffect? _distortEffect;

        public ID2D1Image Output { get; private set; } = null!;

        public DistortChromaEffectProcessor(IGraphicsDevicesAndContext devices, DistortChromaEffect item)
        {
            this.devices = devices;
            this.item = item;
        }

        public void SetInput(ID2D1Image? input) { this.input = input; }

        public DrawDescription Update(EffectDescription effectDescription)
        {
            if (Output != null) { Output.Dispose(); Output = null!; }
            if (this.input == null) return effectDescription.DrawDescription;

            var frame = effectDescription.ItemPosition.Frame;
            var length = effectDescription.ItemDuration.Frame;
            var fps = effectDescription.FPS;

            float amount = (float)item.Amount.GetValue(frame, length, fps);
            float blur = (float)item.Blur.GetValue(frame, length, fps);
            float steps = (float)item.Steps.GetValue(frame, length, fps);
            float angle = (float)item.Angle.GetValue(frame, length, fps);

            try
            {
                _distortEffect ??= new DistortChromaCustomEffect(devices);
            }
            catch
            {
                Dispose();
                return effectDescription.DrawDescription;
            }

            _distortEffect.SetInput(0, this.input, true);
            _distortEffect.Amount = amount;
            _distortEffect.Blur = blur;
            _distortEffect.Steps = steps;
            _distortEffect.Angle = angle;

            Output = _distortEffect.Output;

            return effectDescription.DrawDescription;
        }

        public void ClearInput() { this.input = null; }

        public void Dispose()
        {
            _distortEffect?.SetInput(0, null, true); _distortEffect?.Dispose(); _distortEffect = null;
            Output?.Dispose(); Output = null!;
            this.input = null;
        }
    }
}