using System;
using System.IO;
using System.Runtime.InteropServices;
using Vortice;
using Vortice.Direct2D1;
using YukkuriMovieMaker.Commons;
using YukkuriMovieMaker.Player.Video;

namespace DistortChroma
{
    internal class DistortChromaCustomEffect : D2D1CustomShaderEffectBase
    {
        public float Amount { set => SetValue((int)Props.Amount, value); }
        public float Blur { set => SetValue((int)Props.Blur, value); }
        public float Steps { set => SetValue((int)Props.Steps, value); }
        public float Angle { set => SetValue((int)Props.Angle, value); }

        public DistortChromaCustomEffect(IGraphicsDevicesAndContext devices) : base(Create<EffectImpl>(devices)) { }

        [StructLayout(LayoutKind.Sequential)]
        struct ConstantBuffer
        {
            public float Amount;
            public float Blur;
            public float Steps;
            public float Angle;
        }

        private enum Props { Amount, Blur, Steps, Angle }

        // ★入力を2つ（描画用 t0, マップ用 t1）にするため 2 を指定
        [CustomEffect(2)]
        private class EffectImpl : D2D1CustomShaderEffectImplBase<EffectImpl>
        {
            private ConstantBuffer constants;

            protected override void UpdateConstants()
            {
                if (drawInformation != null) drawInformation.SetPixelShaderConstantBuffer(constants);
            }

            public override void MapInputRectsToOutputRect(RawRect[] inputRects, RawRect[] inputOpaqueSubRects, out RawRect outputRect, out RawRect outputOpaqueSubRect)
            {
                if (inputRects.Length > 0) outputRect = inputRects[0];
                else outputRect = new RawRect();
                outputOpaqueSubRect = new RawRect();
            }

            public override void MapOutputRectToInputRects(RawRect outputRect, RawRect[] inputRects)
            {
                int margin = (int)(Math.Abs(constants.Amount) + constants.Blur * 3.0f) + 5;

                var expandedRect = new RawRect(
                    outputRect.Left - margin, outputRect.Top - margin,
                    outputRect.Right + margin, outputRect.Bottom + margin
                );

                // 入力0（自身）と入力1（マップ）の両方に余白付きの範囲を要求する
                if (inputRects.Length > 0) inputRects[0] = expandedRect;
                if (inputRects.Length > 1) inputRects[1] = expandedRect;
            }

            private static byte[] LoadShader()
            {
                var assembly = System.Reflection.Assembly.GetExecutingAssembly();
                using var stream = assembly.GetManifestResourceStream("DistortChroma.Shaders.DistortChromaShader.cso");
                if (stream == null) throw new FileNotFoundException("DistortChromaShader.cso not found");
                using var ms = new MemoryStream();
                stream.CopyTo(ms);
                return ms.ToArray();
            }

            public EffectImpl() : base(LoadShader())
            {
                constants = new ConstantBuffer { Amount = 10f, Blur = 3f, Steps = 10f, Angle = 0f };
            }

            [CustomEffectProperty(PropertyType.Float, (int)Props.Amount)] public float Amount { get => constants.Amount; set { constants.Amount = value; UpdateConstants(); } }
            [CustomEffectProperty(PropertyType.Float, (int)Props.Blur)] public float Blur { get => constants.Blur; set { constants.Blur = value; UpdateConstants(); } }
            [CustomEffectProperty(PropertyType.Float, (int)Props.Steps)] public float Steps { get => constants.Steps; set { constants.Steps = value; UpdateConstants(); } }
            [CustomEffectProperty(PropertyType.Float, (int)Props.Angle)] public float Angle { get => constants.Angle; set { constants.Angle = value; UpdateConstants(); } }
        }
    }
}