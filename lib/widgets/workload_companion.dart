import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/companion_dialogue_service.dart';
import '../services/companion_rig_service.dart';
import 'rigged_companion.dart';

enum CompanionState { idle, checkTask, celebrate, sleepy, reminder }

class WorkloadCompanion extends StatefulWidget {
  const WorkloadCompanion({
    super.key,
    required this.current,
    required this.limit,
    required this.onTap,
    this.stashedCount = 0,
    this.compact = false,
    this.reminderActive = false,
    this.edgePeek = false,
    this.peekFromLeft = false,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final int current;
  final int limit;
  final VoidCallback onTap;
  final int stashedCount;
  final bool compact;
  final bool reminderActive;
  final bool edgePeek;
  final bool peekFromLeft;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  State<WorkloadCompanion> createState() => WorkloadCompanionState();
}

class WorkloadCompanionState extends State<WorkloadCompanion>
    with TickerProviderStateMixin {
  final math.Random _random = math.Random();
  final CompanionDialogueService _dialogueService = CompanionDialogueService();
  Timer? _idleTimer;
  Timer? _resetTimer;
  Timer? _stateTimer;
  Timer? _dialogueTimer;
  Timer? _peekTimer;
  late final AnimationController _motionController;
  late final AnimationController _stateController;
  double _walkOffset = 0;
  double _walkDirection = 1;
  bool _walking = false;
  bool _blink = false;
  String? _eatingTask;
  bool _hasShownIdleEvent = false;
  bool _traveling = false;
  bool _edgeRevealed = false;
  double _edgeYOffset = 0;
  String? _dialogue;
  CompanionState? _transientState;

  double get _ratio => widget.limit <= 0 ? 0 : widget.current / widget.limit;

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _stateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _scheduleIdleEvent();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _resetTimer?.cancel();
    _stateTimer?.cancel();
    _dialogueTimer?.cancel();
    _peekTimer?.cancel();
    _motionController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  void _stopMotion() {
    _motionController
      ..stop()
      ..value = 0;
    _walking = false;
    _walkDirection = 1;
  }

  CompanionState get _effectiveState {
    final transientState = _transientState;
    if (transientState != null) return transientState;
    if (widget.reminderActive) return CompanionState.reminder;
    if (_ratio >= 1) return CompanionState.sleepy;
    return CompanionState.idle;
  }

  void showState(
    CompanionState state, {
    Duration duration = const Duration(milliseconds: 1400),
  }) {
    _stateTimer?.cancel();
    setState(() {
      _transientState = state == CompanionState.idle ? null : state;
      if (widget.edgePeek) _edgeRevealed = true;
    });
    if (widget.edgePeek) {
      unawaited(showRandomDialogue(_momentForState(state)));
    }
    if (state == CompanionState.idle) return;
    _stateTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() => _transientState = null);
    });
  }

  CompanionDialogueMoment _momentForState(CompanionState state) =>
      switch (state) {
        CompanionState.checkTask => CompanionDialogueMoment.checkTask,
        CompanionState.celebrate => CompanionDialogueMoment.celebrate,
        CompanionState.sleepy => CompanionDialogueMoment.sleepy,
        CompanionState.reminder => CompanionDialogueMoment.reminder,
        CompanionState.idle => _timeMoment,
      };

  CompanionDialogueMoment get _timeMoment {
    final hour = DateTime.now().hour;
    if (hour < 10) return CompanionDialogueMoment.morning;
    if (hour >= 22) return CompanionDialogueMoment.night;
    return CompanionDialogueMoment.daytime;
  }

  Future<void> showRandomDialogue(
    CompanionDialogueMoment moment, {
    Duration cooldown = const Duration(seconds: 8),
  }) async {
    final line = await _dialogueService.pick(
      moment: moment,
      cooldown: cooldown,
    );
    if (!mounted || line == null) return;
    _dialogueTimer?.cancel();
    _peekTimer?.cancel();
    setState(() {
      _dialogue = line;
      if (widget.edgePeek) _edgeRevealed = true;
    });
    _dialogueTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _dialogue = null);
    });
    if (widget.edgePeek) _scheduleEdgeHide();
  }

  void _scheduleEdgeHide([Duration delay = const Duration(seconds: 6)]) {
    _peekTimer?.cancel();
    _peekTimer = Timer(delay, () {
      if (!mounted || _walking || _traveling || _eatingTask != null) return;
      setState(() => _edgeRevealed = false);
    });
  }

  void _startWalk() {
    final target = (_random.nextDouble() * 16) + 7;
    final direction = _random.nextBool() ? 1.0 : -1.0;
    setState(() {
      _hasShownIdleEvent = true;
      _walking = true;
      _walkDirection = direction;
      _walkOffset = target * direction;
      if (widget.edgePeek) {
        _edgeRevealed = true;
        _edgeYOffset = (target * .65 * direction).clamp(0.0, 18.0).toDouble();
        _walkOffset = 0;
      }
      _blink = false;
    });
    _motionController.repeat();
    _resetTimer = Timer(const Duration(milliseconds: 680), () {
      if (!mounted) return;
      setState(() {
        _walkDirection = -direction;
        _walkOffset = 0;
        _edgeYOffset = 0;
      });
      _resetTimer = Timer(const Duration(milliseconds: 680), () {
        if (!mounted) return;
        setState(_stopMotion);
        if (widget.edgePeek) _scheduleEdgeHide(const Duration(seconds: 3));
        _scheduleIdleEvent();
      });
    });
  }

  void _startBlink() {
    setState(() {
      _hasShownIdleEvent = true;
      _blink = true;
    });
    _resetTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() => _blink = false);
      _scheduleIdleEvent();
    });
  }

  void _scheduleIdleEvent() {
    _idleTimer?.cancel();
    final delay = widget.edgePeek
        ? _hasShownIdleEvent
              ? Duration(seconds: 14 + _random.nextInt(13))
              : Duration(seconds: 4 + _random.nextInt(4))
        : _hasShownIdleEvent
        ? Duration(seconds: 6 + _random.nextInt(5))
        : Duration(seconds: 2 + _random.nextInt(3));
    _idleTimer = Timer(delay, () {
      if (!mounted || _eatingTask != null || _traveling) return;
      final route = ModalRoute.of(context);
      final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
      if (keyboardVisible || (route != null && !route.isCurrent)) {
        _scheduleIdleEvent();
        return;
      }
      if (widget.edgePeek && _random.nextInt(3) == 0) {
        _hasShownIdleEvent = true;
        unawaited(showRandomDialogue(_timeMoment));
        _scheduleIdleEvent();
      } else if (!_hasShownIdleEvent || _random.nextInt(3) != 0) {
        _startWalk();
      } else {
        _startBlink();
      }
    });
  }

  void eatTask(String title) {
    _idleTimer?.cancel();
    _resetTimer?.cancel();
    _motionController
      ..stop()
      ..value = 0;
    setState(() {
      _eatingTask = title;
      _transientState = CompanionState.checkTask;
      _walkOffset = 0;
      _walking = false;
      _blink = false;
      if (widget.edgePeek) _edgeRevealed = true;
    });
    if (widget.edgePeek) {
      unawaited(showRandomDialogue(CompanionDialogueMoment.checkTask));
    }
    _resetTimer = Timer(const Duration(milliseconds: 1250), () {
      if (!mounted) return;
      setState(() {
        _eatingTask = null;
        _transientState = null;
      });
      if (widget.edgePeek) _scheduleEdgeHide(const Duration(seconds: 3));
      _scheduleIdleEvent();
    });
  }

  void startJourney([Duration duration = const Duration(milliseconds: 3000)]) {
    _idleTimer?.cancel();
    _resetTimer?.cancel();
    _motionController.repeat();
    setState(() {
      _traveling = true;
      _transientState = CompanionState.checkTask;
      _walkOffset = 0;
      _walking = true;
      _blink = false;
      if (widget.edgePeek) _edgeRevealed = true;
    });
    if (widget.edgePeek) {
      unawaited(showRandomDialogue(CompanionDialogueMoment.stash));
    }
    _resetTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _traveling = false;
        _transientState = null;
        _stopMotion();
      });
      if (widget.edgePeek) _scheduleEdgeHide(const Duration(seconds: 3));
      _scheduleIdleEvent();
    });
  }

  String get _message => switch (_ratio) {
    <= 0.4 => '今日任务状态不错',
    <= 0.7 => '今日任务刚刚好',
    <= 1.0 => '留点精力给自己',
    _ => '今天已经很满了',
  };

  Color _accent(BuildContext context) => switch (_ratio) {
    <= 0.4 => const Color(0xFF5F8D68),
    <= 0.7 => Theme.of(context).colorScheme.primary,
    <= 1.0 => const Color(0xFFE08A3E),
    _ => const Color(0xFFD85A61),
  };

  void _handleEdgeTap() {
    if (!_edgeRevealed) {
      setState(() => _edgeRevealed = true);
      unawaited(showRandomDialogue(_timeMoment, cooldown: Duration.zero));
      _scheduleEdgeHide(const Duration(seconds: 3));
      return;
    }
    widget.onTap();
  }

  Widget _buildEdgePeek(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = _accent(context);
    return Semantics(
      button: true,
      label: '今日负荷 ${widget.current}/${widget.limit}，$_message',
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_dialogue != null)
              Positioned(
                key: const ValueKey('companion-dialogue'),
                right: widget.peekFromLeft ? null : 48,
                left: widget.peekFromLeft ? 48 : null,
                top: 3,
                child: IgnorePointer(
                  child: Material(
                    elevation: 4,
                    color: colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        child: Text(
                          _dialogue!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              right: widget.peekFromLeft ? null : (_edgeRevealed ? 0 : -24),
              left: widget.peekFromLeft ? (_edgeRevealed ? 0 : -24) : null,
              top: _edgeYOffset,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _motionController,
                  _stateController,
                ]),
                builder: (context, _) => _CompanionSprite(
                  state: _effectiveState,
                  size: 48,
                  progress: _stateController.value,
                  ratio: _ratio,
                  accent: accent,
                  surface: colors.surface,
                  ink: colors.onSurface,
                  blink: _blink,
                  walking: _walking,
                  walkProgress: _motionController.value,
                  walkDirection: _walkDirection,
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('companion-edge-tap-target'),
                behavior: HitTestBehavior.opaque,
                onTap: _handleEdgeTap,
                onPanUpdate: (details) =>
                    widget.onDragUpdate?.call(details.delta),
                onPanEnd: (_) => widget.onDragEnd?.call(),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.edgePeek) return _buildEdgePeek(context);
    final colors = Theme.of(context).colorScheme;
    final accent = _accent(context);
    return Semantics(
      button: true,
      label: '今日负荷 ${widget.current}/${widget.limit}，$_message',
      child: Material(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: widget.compact ? 72 : 242,
            height: widget.compact ? 50 : 70,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 620),
                  curve: Curves.easeInOut,
                  left: widget.compact
                      ? 1 + (_walkOffset * .18)
                      : 8 + _walkOffset,
                  top: widget.compact ? 1 : 6,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _motionController,
                      _stateController,
                    ]),
                    builder: (context, _) => _CompanionSprite(
                      state: _effectiveState,
                      size: widget.compact ? 48 : 58,
                      progress: _stateController.value,
                      ratio: _ratio,
                      accent: accent,
                      surface: colors.surface,
                      ink: colors.onSurface,
                      blink: _blink,
                      walking: _walking,
                      walkProgress: _motionController.value,
                      walkDirection: _walkDirection,
                    ),
                  ),
                ),
                if (!widget.compact)
                  Positioned(
                    left: 76,
                    right: 12,
                    top: 13,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _message,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${widget.current}/${widget.limit}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: _ratio.clamp(0.0, 1.0).toDouble(),
                            minHeight: 5,
                            color: accent,
                            backgroundColor: accent.withAlpha(35),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.compact)
                  Positioned(
                    right: 3,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(24),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '${widget.current}/${widget.limit}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                if (!widget.compact && _eatingTask != null)
                  TweenAnimationBuilder<double>(
                    key: ValueKey(_eatingTask),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeInCubic,
                    builder: (context, value, child) => Positioned(
                      left: 155 - (112 * value),
                      top: 23 + (4 * value),
                      child: Opacity(
                        opacity: 1 - (value * .85),
                        child: Transform.scale(
                          scale: 1 - (value * .55),
                          child: child,
                        ),
                      ),
                    ),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 112),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        _eatingTask!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanionSprite extends StatelessWidget {
  const _CompanionSprite({
    required this.state,
    required this.size,
    required this.progress,
    required this.ratio,
    required this.accent,
    required this.surface,
    required this.ink,
    required this.blink,
    required this.walking,
    required this.walkProgress,
    required this.walkDirection,
  });

  static const assetPath = 'assets/mascot/todolist-mascot.webp';

  final CompanionState state;
  final double size;
  final double progress;
  final double ratio;
  final Color accent;
  final Color surface;
  final Color ink;
  final bool blink;
  final bool walking;
  final double walkProgress;
  final double walkDirection;

  @override
  Widget build(BuildContext context) {
    final wave = math.sin(progress * math.pi * 2);
    var y = wave * .7;
    var angle = wave * .008;
    var scale = 1 + wave * .008;
    var opacity = 1.0;

    switch (state) {
      case CompanionState.idle:
        break;
      case CompanionState.checkTask:
        y -= 1.2;
        angle -= .035;
        scale += .02;
        break;
      case CompanionState.celebrate:
        y -= wave.abs() * 5;
        angle += wave * .075;
        scale += wave.abs() * .055;
        break;
      case CompanionState.sleepy:
        y += 1.5;
        angle -= .025;
        opacity = .9;
        break;
      case CompanionState.reminder:
        y -= 1;
        angle += math.sin(progress * math.pi * 4) * .045;
        break;
    }

    if (walking) {
      final step = math.sin(walkProgress * math.pi * 2);
      y -= step.abs() * 2.2;
      angle += step * .025 * walkDirection;
    }

    final direction = walking
        ? walkDirection < 0
              ? CompanionDirection.left
              : CompanionDirection.right
        : CompanionDirection.front;
    final idleMotion = CompanionMotion(
      bodyOffset: Offset(0, y),
      bodyRotation: angle,
      bodyScale: scale,
      parts: {'earring_pendant': CompanionPartPose(rotation: wave * .035)},
    );
    final motion = walking
        ? CompanionMotion.walk(walkProgress, movingLeft: walkDirection < 0)
        : idleMotion;

    return SizedBox.square(
      key: ValueKey('companion-mascot-${state.name}'),
      dimension: size,
      child: Opacity(
        opacity: opacity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RiggedCompanion(
                size: size,
                direction: direction,
                motion: motion,
                fallback: Image.asset(
                  assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => CustomPaint(
                    painter: _ChibiCompanionPainter(
                      ratio: ratio,
                      accent: accent,
                      surface: surface,
                      ink: ink,
                      blink: blink,
                      walking: walking,
                      walkProgress: walkProgress,
                      walkDirection: walkDirection,
                    ),
                  ),
                ),
              ),
            ),
            if (state == CompanionState.checkTask)
              Positioned(
                right: -1,
                top: 2,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: size * .24,
                  color: const Color(0xFF5F8D68),
                ),
              ),
            if (state == CompanionState.celebrate)
              Positioned(
                right: -2,
                top: -2,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: size * .27,
                  color: const Color(0xFFF2A93B),
                ),
              ),
            if (state == CompanionState.sleepy)
              Positioned(
                right: -1,
                top: 0,
                child: Text(
                  'Zz',
                  style: TextStyle(
                    color: accent,
                    fontSize: size * .2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (state == CompanionState.reminder)
              Positioned(
                right: -1,
                top: 1,
                child: Icon(
                  Icons.notifications_active_rounded,
                  size: size * .25,
                  color: const Color(0xFFE08A3E),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CompanionTaskEvent extends StatelessWidget {
  const CompanionTaskEvent({
    super.key,
    required this.taskTitle,
    required this.ratio,
    this.rightInset = 0,
  });

  final String taskTitle;
  final double ratio;
  final double rightInset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final usableWidth = math.max(280.0, constraints.maxWidth - rightInset);
        final targetY = (constraints.maxHeight * .42)
            .clamp(150.0, 330.0)
            .toDouble();
        final taskWidth = math.min(230.0, usableWidth - 44);
        final taskX = 22.0;
        final targetX = math.min(taskX + taskWidth - 32, usableWidth - 92);
        final startX = usableWidth - 84;
        final nestX = (usableWidth * .54)
            .clamp(150.0, usableWidth - 84)
            .toDouble();

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 3000),
          curve: Curves.easeInOut,
          builder: (context, progress, _) {
            final approaching = progress < .34;
            final reaching = progress >= .34 && progress < .50;
            final lifting = progress >= .50 && progress < .62;
            final carrying = progress >= .62 && progress < .88;
            final puttingDown = progress >= .88;
            final approachProgress = (progress / .34)
                .clamp(0.0, 1.0)
                .toDouble();
            final reachProgress = ((progress - .34) / .16)
                .clamp(0.0, 1.0)
                .toDouble();
            final carryProgress = ((progress - .62) / .26)
                .clamp(0.0, 1.0)
                .toDouble();
            final putProgress = ((progress - .88) / .12)
                .clamp(0.0, 1.0)
                .toDouble();
            final companionX = approaching
                ? startX +
                      (targetX - startX) *
                          Curves.easeInOut.transform(approachProgress)
                : carrying || puttingDown
                ? targetX +
                      (nestX - targetX) *
                          Curves.easeInOut.transform(carryProgress)
                : targetX;
            final companionY = approaching
                ? 18 +
                      (targetY - 18) *
                          Curves.easeInOut.transform(approachProgress)
                : carrying || puttingDown
                ? targetY +
                      (24 - targetY) * Curves.easeInOut.transform(carryProgress)
                : targetY;
            final message = approaching
                ? '小精灵正跑过去…'
                : reaching || lifting
                ? '蹲稳，双手抱起来'
                : carrying
                ? '抱稳啦，慢慢搬回去'
                : '轻轻放进精灵窝';
            final gripping = lifting || carrying || putProgress < .7;
            final direction = approaching
                ? CompanionDirection.left
                : carrying || puttingDown
                ? CompanionDirection.right
                : CompanionDirection.front;
            final motion = approaching
                ? CompanionMotion.walk((progress * 9) % 1, movingLeft: true)
                : reaching
                ? CompanionMotion.reach(reachProgress)
                : lifting
                ? CompanionMotion.reach(
                    1 - ((progress - .50) / .12),
                    gripping: true,
                  )
                : carrying
                ? CompanionMotion.carry((progress * 9) % 1, movingLeft: false)
                : CompanionMotion.reach(putProgress, gripping: gripping);

            Widget heldTask() => Material(
              elevation: 3,
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                child: Text(
                  taskTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 12,
                  left: math.max(12, usableWidth / 2 - 92),
                  child: Material(
                    elevation: 5,
                    color: colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: taskX,
                  top: targetY + 24,
                  child: Opacity(
                    opacity: progress < .50 ? 1 : 0,
                    child: Material(
                      elevation: 7,
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: taskWidth,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.radio_button_unchecked,
                              size: 17,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                taskTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (carrying || puttingDown)
                  Positioned(
                    left: nestX + 46,
                    top: 42,
                    child: Icon(
                      Icons.inventory_2_rounded,
                      size: 34,
                      color: colors.primary,
                    ),
                  ),
                if (puttingDown && putProgress >= .7)
                  Positioned(
                    left: nestX + 16,
                    top: 69,
                    width: 92,
                    height: 38,
                    child: heldTask(),
                  ),
                Positioned(
                  left: companionX,
                  top: companionY,
                  child: RiggedCompanion(
                    key: const ValueKey('companion-task-rig'),
                    size: 82,
                    direction: direction,
                    motion: motion,
                    taskCard: gripping ? heldTask() : null,
                    fallback: Image.asset(
                      _CompanionSprite.assetPath,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ChibiCompanionPainter extends CustomPainter {
  const _ChibiCompanionPainter({
    required this.ratio,
    required this.accent,
    required this.surface,
    required this.ink,
    required this.blink,
    required this.walking,
    required this.walkProgress,
    required this.walkDirection,
  });

  final double ratio;
  final Color accent;
  final Color surface;
  final Color ink;
  final bool blink;
  final bool walking;
  final double walkProgress;
  final double walkDirection;

  Offset _joint(Offset origin, double angle, double length) {
    return origin + Offset(math.sin(angle) * length, math.cos(angle) * length);
  }

  void _drawLeg(
    Canvas canvas, {
    required Offset hip,
    required double phase,
    required Paint outline,
    required Paint skin,
    required Paint shoe,
  }) {
    final thighAngle = phase * .5;
    final knee = _joint(hip, thighAngle, 5.8);
    final kneeBend = math.max(0.0, -phase) * .38;
    final ankle = _joint(knee, thighAngle - kneeBend, 5.2);

    canvas.drawLine(hip, knee, outline..strokeWidth = 5.4);
    canvas.drawLine(hip, knee, skin..strokeWidth = 3.9);
    canvas.drawCircle(knee, 2.15, outline..style = PaintingStyle.fill);
    canvas.drawCircle(knee, 1.45, skin..style = PaintingStyle.fill);
    canvas.drawLine(knee, ankle, outline..strokeWidth = 5.0);
    canvas.drawLine(knee, ankle, skin..strokeWidth = 3.55);

    final footCenter = ankle + Offset(phase * 1.1, 1.15);
    canvas.save();
    canvas.translate(footCenter.dx, footCenter.dy);
    canvas.rotate(-phase * .18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-3.3, -1.7, 6.6, 3.9),
        const Radius.circular(1.8),
      ),
      outline..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-2.65, -1.25, 5.3, 2.8),
        const Radius.circular(1.4),
      ),
      shoe..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  void _drawArm(
    Canvas canvas, {
    required Offset shoulder,
    required double phase,
    required bool bandaged,
    required Paint outline,
    required Paint skin,
    required Paint bandage,
  }) {
    final upperAngle = phase * .58;
    final elbow = _joint(shoulder, upperAngle, 5.2);
    final wrist = _joint(elbow, upperAngle - phase * .12, 4.6);

    canvas.drawLine(shoulder, elbow, outline..strokeWidth = 5.0);
    canvas.drawLine(shoulder, elbow, skin..strokeWidth = 3.55);
    canvas.drawCircle(elbow, 2, outline..style = PaintingStyle.fill);
    canvas.drawCircle(elbow, 1.3, skin..style = PaintingStyle.fill);
    canvas.drawLine(elbow, wrist, outline..strokeWidth = 4.6);
    canvas.drawLine(
      elbow,
      wrist,
      (bandaged ? bandage : skin)..strokeWidth = 3.25,
    );
    canvas.drawCircle(wrist, 2.15, outline..style = PaintingStyle.fill);
    canvas.drawCircle(wrist, 1.45, skin..style = PaintingStyle.fill);

    if (bandaged) {
      final delta = wrist - elbow;
      final length = delta.distance;
      final unit = delta / length;
      final normal = Offset(-unit.dy, unit.dx);
      final stripe = Paint()
        ..color = const Color(0xFFB7AAA0)
        ..strokeWidth = .55
        ..strokeCap = StrokeCap.round;
      for (final distance in [1.3, 2.7, 3.9]) {
        final center = elbow + unit * distance;
        canvas.drawLine(center - normal * 1.5, center + normal * 1.5, stripe);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 52;
    canvas.save();
    canvas.translate((size.width - 48 * scale) / 2, 0);
    canvas.scale(scale);

    final gait = walking
        ? math.sin(walkProgress * math.pi * 2) * walkDirection
        : 0.0;
    final bob = walking
        ? math.sin(walkProgress * math.pi * 2).abs() * .75
        : 0.0;
    canvas.translate(0, -bob);

    final outlinePaint = Paint()
      ..color = const Color(0xFF3B302C)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final skinPaint = Paint()
      ..color = const Color(0xFFF2C7A8)
      ..strokeCap = StrokeCap.round;
    final bandagePaint = Paint()
      ..color = const Color(0xFFF4F0EA)
      ..strokeCap = StrokeCap.round;
    final shoePaint = Paint()..color = const Color(0xFFF4F1EC);
    final shirtPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFE8E3DE)],
      ).createShader(const Rect.fromLTWH(13, 23, 22, 16));
    final shortsPaint = Paint()..color = const Color(0xFF24242A);
    final facePaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.25, -.35),
        radius: .9,
        colors: [Color(0xFFFFE5D0), Color(0xFFF1C3A3)],
      ).createShader(const Rect.fromLTWH(7, 4, 34, 27));
    final hairPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3A3A42), Color(0xFF101014)],
      ).createShader(const Rect.fromLTWH(7, 0, 34, 22));
    final glassesPaint = Paint()
      ..color = const Color(0xFF7D858C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85;
    final inkPaint = Paint()
      ..color = ink.withAlpha(220)
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(24, 49), width: 25, height: 3.8),
      Paint()..color = accent.withAlpha(32),
    );

    _drawLeg(
      canvas,
      hip: const Offset(19.1, 36.5),
      phase: gait,
      outline: outlinePaint,
      skin: skinPaint,
      shoe: shoePaint,
    );
    _drawLeg(
      canvas,
      hip: const Offset(28.9, 36.5),
      phase: -gait,
      outline: outlinePaint,
      skin: skinPaint,
      shoe: shoePaint,
    );

    _drawArm(
      canvas,
      shoulder: const Offset(14.7, 25.5),
      phase: -gait,
      bandaged: false,
      outline: outlinePaint,
      skin: skinPaint,
      bandage: bandagePaint,
    );
    _drawArm(
      canvas,
      shoulder: const Offset(33.3, 25.5),
      phase: gait,
      bandaged: true,
      outline: outlinePaint,
      skin: skinPaint,
      bandage: bandagePaint,
    );

    final torso = Path()
      ..moveTo(17, 23.2)
      ..quadraticBezierTo(14, 24.2, 13.8, 28)
      ..lineTo(15.2, 36)
      ..quadraticBezierTo(24, 38, 32.8, 36)
      ..lineTo(34.2, 28)
      ..quadraticBezierTo(34, 24.2, 31, 23.2)
      ..close();
    canvas.drawPath(torso, outlinePaint..style = PaintingStyle.fill);
    canvas.save();
    canvas.translate(0, -.5);
    canvas.drawPath(torso, shirtPaint);
    canvas.restore();
    canvas.drawPath(
      torso,
      outlinePaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(14.8, 34.2, 18.4, 5.7),
        const Radius.circular(1.8),
      ),
      shortsPaint,
    );
    canvas.drawLine(
      const Offset(24, 36.3),
      const Offset(24, 39.2),
      Paint()
        ..color = const Color(0xFF0B0B0E)
        ..strokeWidth = .8,
    );

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(7.8, 15.7), width: 6.4, height: 8.8),
      outlinePaint..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(40.2, 15.7),
        width: 6.4,
        height: 8.8,
      ),
      outlinePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(7.8, 15.7), width: 5, height: 7.2),
      skinPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(40.2, 15.7), width: 5, height: 7.2),
      skinPaint,
    );

    final headRect = Rect.fromCenter(
      center: const Offset(24, 14.4),
      width: 32.8,
      height: 26.6,
    );
    canvas.drawOval(headRect, outlinePaint..style = PaintingStyle.fill);
    canvas.drawOval(headRect.deflate(1), facePaint);
    final blushPaint = Paint()..color = const Color(0x50EF8F88);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(14.5, 19.4),
        width: 5.4,
        height: 2.4,
      ),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(33.5, 19.4),
        width: 5.4,
        height: 2.4,
      ),
      blushPaint,
    );

    final hair = Path()
      ..moveTo(7.9, 14.4)
      ..quadraticBezierTo(7.6, 3.8, 18.2, 1.5)
      ..quadraticBezierTo(24, -.2, 29.3, 1.6)
      ..quadraticBezierTo(40.1, 3.9, 40.1, 14.6)
      ..quadraticBezierTo(38.5, 13.2, 36.6, 12.1)
      ..quadraticBezierTo(35.2, 15.4, 32.8, 11.2)
      ..quadraticBezierTo(30.5, 14.2, 28.7, 9.5)
      ..quadraticBezierTo(26.5, 13.6, 24.2, 8.7)
      ..quadraticBezierTo(22.2, 13.2, 19.6, 9.1)
      ..quadraticBezierTo(17.8, 13.9, 15.4, 10.6)
      ..quadraticBezierTo(12.5, 14.8, 7.9, 14.4)
      ..close();
    canvas.drawPath(hair, outlinePaint..style = PaintingStyle.fill);
    canvas.drawPath(hair, hairPaint);
    final hairHighlight = Paint()
      ..color = const Color(0x785C5C66)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(13, 2.2, 12, 10),
      math.pi * 1.05,
      math.pi * .62,
      false,
      hairHighlight,
    );
    canvas.drawArc(
      const Rect.fromLTWH(23, 2, 11, 10),
      math.pi * 1.12,
      math.pi * .55,
      false,
      hairHighlight,
    );

    final leftLens = RRect.fromRectAndRadius(
      const Rect.fromLTWH(10.3, 12.1, 12.2, 8.4),
      const Radius.circular(2.5),
    );
    final rightLens = RRect.fromRectAndRadius(
      const Rect.fromLTWH(25.5, 12.1, 12.2, 8.4),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(leftLens, Paint()..color = surface.withAlpha(58));
    canvas.drawRRect(rightLens, Paint()..color = surface.withAlpha(58));
    canvas.drawRRect(leftLens, glassesPaint);
    canvas.drawRRect(rightLens, glassesPaint);
    canvas.drawLine(
      const Offset(22.5, 15.6),
      const Offset(25.5, 15.6),
      glassesPaint,
    );
    canvas.drawLine(
      const Offset(9.8, 14),
      const Offset(7.4, 13.2),
      glassesPaint,
    );
    canvas.drawLine(
      const Offset(38.2, 14),
      const Offset(40.6, 13.2),
      glassesPaint,
    );

    if (blink) {
      canvas.drawLine(
        const Offset(14.8, 16.5),
        const Offset(18.3, 16.5),
        inkPaint,
      );
      canvas.drawLine(
        const Offset(29.7, 16.5),
        const Offset(33.2, 16.5),
        inkPaint,
      );
    } else if (ratio > 1) {
      canvas.drawLine(
        const Offset(14.8, 15.8),
        const Offset(18.2, 17.2),
        inkPaint,
      );
      canvas.drawLine(
        const Offset(29.8, 17.2),
        const Offset(33.2, 15.8),
        inkPaint,
      );
    } else {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(16.6, 16.3),
          width: 2.25,
          height: 4.3,
        ),
        inkPaint..style = PaintingStyle.fill,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(31.4, 16.3),
          width: 2.25,
          height: 4.3,
        ),
        inkPaint,
      );
    }

    final mouth = Path()
      ..moveTo(21.7, 21.8)
      ..lineTo(23.2, 20.5)
      ..lineTo(24.8, 21.8)
      ..lineTo(26.3, 20.5);
    if (ratio > .7) mouth.relativeLineTo(1.4, 1.3);
    canvas.drawPath(
      mouth,
      inkPaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChibiCompanionPainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.accent != accent ||
        oldDelegate.surface != surface ||
        oldDelegate.ink != ink ||
        oldDelegate.blink != blink ||
        oldDelegate.walking != walking ||
        oldDelegate.walkProgress != walkProgress ||
        oldDelegate.walkDirection != walkDirection;
  }
}
