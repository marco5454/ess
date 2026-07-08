import 'package:flutter/material.dart';

/// Central motion vocabulary for the app.
///
/// Everything on screen should share a small, opinionated set of durations
/// and curves so movement feels intentional rather than a hodge-podge of
/// per-widget guesses.
class MotionDurations {
  MotionDurations._();

  /// Micro-interactions (button press, toggle flip, tap ripple hint).
  static const fast = Duration(milliseconds: 120);

  /// Standard entrance/exit for widgets that appear inline (banners,
  /// list rows fading in, dialogs slide-in). This is the default.
  static const medium = Duration(milliseconds: 260);

  /// Larger movements — full-page transitions, section reveals.
  static const slow = Duration(milliseconds: 380);

  /// Shimmer sweep period. Long enough to feel like a soft loading state
  /// and short enough that the user notices motion.
  static const shimmerCycle = Duration(milliseconds: 1400);
}

class MotionCurves {
  MotionCurves._();

  /// Default entering curve. Feels like a soft settle.
  static const enter = Curves.easeOutCubic;

  /// Default exiting curve. Pulls away decisively but not abruptly.
  static const exit = Curves.easeInCubic;

  /// For pressed / released micro-interactions on tappable surfaces.
  static const emphasis = Curves.easeOutBack;
}

/// A fire-and-forget "appear" animation: fades a child in from 0 → 1 and
/// slides it up by [offset] pixels. Use this to soften the moment when
/// content lands from an async fetch, or when a list first paints.
///
/// The animation only runs once on first build — subsequent state changes
/// leave the child in its final position.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = MotionDurations.medium,
    this.delay = Duration.zero,
    this.offset = 12.0,
    this.curve = MotionCurves.enter,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;

  /// Distance in logical pixels the child rises from. Positive = starts
  /// below its final position (the visually settling motion).
  final double offset;
  final Curve curve;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _t = CurvedAnimation(parent: _controller, curve: widget.curve);
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: _t.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _t.value) * widget.offset),
            child: child,
          ),
        );
      },
    );
  }
}

/// A shimmer sweep used inside skeleton loaders. Paints a moving light
/// band across its child using [ShaderMask]. The child itself should be
/// a set of solid-colored placeholder shapes.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.period = MotionDurations.shimmerCycle,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration period;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Default palette leans on surface tones so the sweep is subtle over
    // the cream background.
    final base = widget.baseColor ?? scheme.surfaceContainerHighest;
    final highlight =
        widget.highlightColor ?? scheme.surfaceContainerLowest;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final t = _controller.value;
            // Sweep from left (-1) to right (+2) so the band clearly enters
            // and exits, giving a brief "rest" between passes.
            final dx = -1.0 + 3.0 * t;
            return LinearGradient(
              begin: Alignment(dx - 0.4, 0),
              end: Alignment(dx + 0.4, 0),
              colors: [base, highlight, base],
              stops: const [0.25, 0.5, 0.75],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
    );
  }
}

/// A single solid placeholder block — pair with [Shimmer] for skeleton
/// loaders that mimic the shape of the real content.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A rounded solid circle placeholder, sized to typical avatar / icon
/// slots so list-row skeletons align with the real content.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Wrap a tappable in this to give it a small "press" scale response —
/// content briefly nudges to ~97% on tap-down and springs back.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.duration = MotionDurations.fast,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration duration;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: widget.duration,
        curve: MotionCurves.emphasis,
        child: widget.child,
      ),
    );
  }
}

/// Staggers the entrance of a list of children. Each child gets its own
/// [FadeSlideIn] with a delay = [step] × index, capped at [maxIndex] so
/// long lists don't accumulate a huge total wait.
class StaggeredList extends StatelessWidget {
  const StaggeredList({
    super.key,
    required this.children,
    this.step = const Duration(milliseconds: 35),
    this.maxIndex = 12,
    this.itemDuration = MotionDurations.medium,
  });

  final List<Widget> children;
  final Duration step;
  final int maxIndex;
  final Duration itemDuration;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          FadeSlideIn(
            delay: step * (i.clamp(0, maxIndex)),
            duration: itemDuration,
            child: children[i],
          ),
      ],
    );
  }
}
