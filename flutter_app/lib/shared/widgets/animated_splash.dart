import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Cold-start splash — a small flavor-specific service icon fades in first,
/// then the logo scales/fades in, then the app name + brand tagline follow
/// a beat later. Shown while _SessionGate (app.dart) resolves the saved
/// session; a minimum display time keeps it from flashing by on a fast
/// load (see _SessionGate's Future.wait with a delay alongside the real
/// session fetch).
class AnimatedSplash extends StatefulWidget {
  final String appTitle;
  final IconData serviceIcon;
  const AnimatedSplash({super.key, required this.appTitle, required this.serviceIcon});

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final Animation<double> _iconOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
  );
  late final Animation<double> _logoScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.15, 0.7, curve: Curves.easeOutBack),
  );
  late final Animation<double> _logoOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.15, 0.55, curve: Curves.easeOut),
  );
  late final Animation<double> _titleOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.5, 0.9, curve: Curves.easeOut),
  );
  late final Animation<Offset> _titleSlide = Tween(
    begin: const Offset(0, 0.3),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.5, 0.9, curve: Curves.easeOut)));
  late final Animation<double> _taglineOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: _iconOpacity.value,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(widget.serviceIcon, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset('assets/branding/logo.png', fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeTransition(
                      opacity: _titleOpacity,
                      child: SlideTransition(
                        position: _titleSlide,
                        child: Text(
                          widget.appTitle,
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FadeTransition(
                      opacity: _taglineOpacity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'نوصلك لمكان ما تحب وبنقدملك خدمة مطار مريحة وموثوقة',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600, height: 1.5),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
