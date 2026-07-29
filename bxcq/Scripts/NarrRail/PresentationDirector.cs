using Godot;
using Godot.Collections;

namespace BXCQ.NarrRail;

/// <summary>
/// Stage direction (fade / delay) kept separate from dialogue UI and world rules.
/// </summary>
public partial class PresentationDirector : CanvasLayer
{
	public const string EventFade = "presentation.fade";
	public const string EventDelay = "delay";

	private GodotObject _router = null!;
	private GodotObject _activeSession = null!;
	private ColorRect _fadeRect = null!;
	private bool _busy;

	public bool LastFadeCompleted { get; private set; }

	public override void _Ready()
	{
		Layer = 90;
		_fadeRect = new ColorRect
		{
			Name = "PresentationFade",
			Color = new Color(0f, 0f, 0f, 0f),
			MouseFilter = Control.MouseFilterEnum.Ignore,
			AnchorRight = 1f,
			AnchorBottom = 1f,
			GrowHorizontal = Control.GrowDirection.Both,
			GrowVertical = Control.GrowDirection.Both,
		};
		AddChild(_fadeRect);

		var routerScript = GD.Load<GDScript>("res://addons/narrrail/runtime/narrrail_event_router.gd");
		if (routerScript == null)
		{
			GD.PushError("PresentationDirector: narrrail_event_router.gd missing");
			return;
		}

		_router = (GodotObject)routerScript.New();
		_router.Call("register_type", EventFade, Callable.From((Dictionary payload) => OnFade(payload)));
		_router.Call("register_type", EventDelay, Callable.From((Dictionary payload) => OnDelay(payload)));
		GD.Print("PresentationDirector ready");
	}

	/// <returns>true if this director handled the eventType.</returns>
	public bool TryHandle(Dictionary payload, GodotObject session)
	{
		_activeSession = session;
		return _router.Call("dispatch", payload).AsBool();
	}

	public void ClearSession(GodotObject session)
	{
		if (_activeSession == session)
		{
			_activeSession = null!;
		}
	}

	private void OnFade(Dictionary payload)
	{
		RunFadeAsync(payload);
	}

	private void OnDelay(Dictionary payload)
	{
		RunDelayAsync(payload);
	}

	private async void RunFadeAsync(Dictionary payload)
	{
		if (_busy)
		{
			GD.PushWarning("PresentationDirector: fade skipped (busy)");
			return;
		}

		_busy = true;
		PauseSessionIfPossible();

		var duration = ReadParamFloat(payload, "duration", 0.4f);
		var half = Mathf.Max(0.05f, duration * 0.5f);
		var color = ReadParamColor(payload, new Color(0f, 0f, 0f, 1f));

		GD.Print($"Presentation fade duration={duration:0.##}");

		_fadeRect.Color = new Color(color.R, color.G, color.B, 0f);
		var fadeOut = CreateTween();
		fadeOut.TweenProperty(_fadeRect, "color:a", color.A, half);
		await ToSignal(fadeOut, Tween.SignalName.Finished);

		var fadeIn = CreateTween();
		fadeIn.TweenProperty(_fadeRect, "color:a", 0f, half);
		await ToSignal(fadeIn, Tween.SignalName.Finished);

		_busy = false;
		LastFadeCompleted = true;
		ResumeSessionIfPossible();
	}

	private async void RunDelayAsync(Dictionary payload)
	{
		if (_busy)
		{
			GD.PushWarning("PresentationDirector: delay skipped (busy)");
			return;
		}

		_busy = true;
		PauseSessionIfPossible();

		var seconds = Mathf.Max(0f, ReadParamFloat(payload, "time", 0.3f));
		GD.Print($"Presentation delay time={seconds:0.##}");
		if (seconds > 0f)
		{
			await ToSignal(GetTree().CreateTimer(seconds), SceneTreeTimer.SignalName.Timeout);
		}

		_busy = false;
		ResumeSessionIfPossible();
	}

	private void PauseSessionIfPossible()
	{
		if (_activeSession == null)
		{
			return;
		}

		_activeSession.Call("pause");
	}

	private void ResumeSessionIfPossible()
	{
		if (_activeSession == null)
		{
			return;
		}

		_activeSession.Call("resume");
	}

	private static float ReadParamFloat(Dictionary payload, string key, float fallback)
	{
		if (!payload.ContainsKey("params") || payload["params"].VariantType != Variant.Type.Dictionary)
		{
			return fallback;
		}

		var parameters = payload["params"].AsGodotDictionary();
		if (!parameters.ContainsKey(key))
		{
			return fallback;
		}

		return parameters[key].AsSingle();
	}

	private static Color ReadParamColor(Dictionary payload, Color fallback)
	{
		if (!payload.ContainsKey("params") || payload["params"].VariantType != Variant.Type.Dictionary)
		{
			return fallback;
		}

		var parameters = payload["params"].AsGodotDictionary();
		if (!parameters.ContainsKey("color"))
		{
			return fallback;
		}

		// Optional "r,g,b,a" string; otherwise keep fallback.
		var raw = parameters["color"].AsString();
		var parts = raw.Split(',');
		if (parts.Length < 3)
		{
			return fallback;
		}

		if (!float.TryParse(parts[0].Trim(), out var r) ||
			!float.TryParse(parts[1].Trim(), out var g) ||
			!float.TryParse(parts[2].Trim(), out var b))
		{
			return fallback;
		}

		var a = 1f;
		if (parts.Length >= 4 && float.TryParse(parts[3].Trim(), out var parsedA))
		{
			a = parsedA;
		}

		return new Color(r, g, b, a);
	}
}
