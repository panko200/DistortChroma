using DistortChroma;
using System;
using Vortice;
using Vortice.Direct2D1;
using Vortice.Mathematics;
using YukkuriMovieMaker.Commons;
using YukkuriMovieMaker.Player.Video;
using YukkuriMovieMaker.Plugin.Brush;

namespace DistortChroma
{
    internal class DistortChromaEffectProcessor : IVideoEffectProcessor, IDisposable
    {
        private readonly DistortChromaEffect item;
        private readonly IGraphicsDevicesAndContext devices;
        private ID2D1Image? input;
        private DistortChromaCustomEffect? _distortEffect;

        private IBrushSource? brushSource;
        private ID2D1CommandList? patternCommandList;

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

            // ソースに「別の画像・シーン」が選ばれている場合
            if (item.SourceMode == DistortChromaMapSource.Other)
            {
                brushSource ??= item.Brush.CreateBrush(devices);
                brushSource.Update((TimelineItemSourceDescription)effectDescription);

                var deviceContext = devices.DeviceContext;
                var bounds = deviceContext.GetImageLocalBounds(this.input);

                patternCommandList?.Dispose();
                patternCommandList = deviceContext.CreateCommandList();

                deviceContext.Target = patternCommandList;
                deviceContext.BeginDraw();
                deviceContext.Clear(null);

                // ★ 最適化：巨大なパッド付き(rect)ではなく、元の画像サイズ(bounds)に描画を限定します。
                // これにより、どれだけ歪み強度を大きくしても、別画像・シーンのレンダリング負荷が肥大化しません。
                deviceContext.FillRectangle(bounds, brushSource.Brush);

                deviceContext.EndDraw();
                deviceContext.Target = null;
                patternCommandList.Close();

                _distortEffect.SetInput(1, patternCommandList, true); // t1に画像を渡す
            }
            else
            {
                // アイテム自身をソースとする場合
                _distortEffect.SetInput(1, this.input, true); // t1に自身を渡す
            }

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
            _distortEffect?.SetInput(0, null, true);
            _distortEffect?.SetInput(1, null, true);
            _distortEffect?.Dispose(); _distortEffect = null;

            patternCommandList?.Dispose(); patternCommandList = null;
            brushSource?.Dispose(); brushSource = null;

            Output?.Dispose(); Output = null!;
            this.input = null;
        }
    }
}