// 横向滑动识别器（列表行的「滑动连选」）。
//
// ── 为什么不能用内置的 HorizontalDragGestureRecognizer ──
//   1. 竞技场按命中测试顺序加入，**内层先注册、先处理事件**。ListView 的
//      纵向滚动识别器挂在 Scrollable 上，是行的祖先；横滑识别器必须挂在
//      **每一行内部**（比 Scrollable 更深）才抢得过它。
//   2. 内置识别器要求横向位移大于纵向才胜出。而「斜着扫过几行连选」的
//      纵向分量天然很大（实测 45° 斜向时事件列表为空，一个事件都收不到），
//      必须换成方向比例判定。
//
// ── 判定逻辑（用测试矩阵逐条验证过）──
//   横向累计位移 > slop(6)  且  横向 > 纵向 × ratio(0.2)
//   一旦满足立即 resolve(accepted) 赢下竞技场，之后的纵向移动全部用于
//   扩展选中区间，列表不再滚动。
//
//   为什么 slop 取 6：列表滚动在纵向 18px(kTouchSlop) 时才胜出。对 45°
//   斜向，横向到 6px 时纵向才 6px；对更陡的斜向（如 25x100），横向到 6px
//   时纵向约 24px —— 因为本识别器在事件派发中更靠内、先拿到事件，仍能
//   抢在列表滚动之前接受。
//   为什么 ratio 取 0.2：斜着扫（40x110 → 0.36、25x100 → 0.25）都能满足；
//   而纵向滚动时横向抖动通常不到纵向的 0.1 倍（实测 12x150 → 0.08），
//   不会误触发。
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 横向位移阈值（px）
const double kSwipeSelectSlop = 6;

/// 方向比例阈值：横向分量至少要是纵向的这么多倍，才认定为「横向滑动」。
/// 0.2 ≈ 与竖直方向夹角小于 79°。
const double kSwipeSelectRatio = 0.2;

class SwipeSelectRecognizer extends OneSequenceGestureRecognizer {
  SwipeSelectRecognizer({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.slop = kSwipeSelectSlop,
    this.ratio = kSwipeSelectRatio,
  });

  /// 手势被接受时回调，携带**按下时**的全局坐标（用于确定起始行）。
  /// 返回 false 表示这一行不参与选择（例如「..」行），此时主动让出竞技场。
  bool Function(Offset global) onStart;

  /// 手指移动中回调，携带当前位置
  void Function(Offset global) onUpdate;

  /// 手势结束回调
  VoidCallback onEnd;

  /// 横向位移阈值
  final double slop;

  /// 方向比例阈值（横向 / 纵向）
  final double ratio;

  Offset _downPosition = Offset.zero;
  double _dx = 0;
  double _dy = 0;
  bool _accepted = false;
  bool _ended = false;

  @override
  String get debugDescription => 'swipe-select';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _downPosition = event.position;
    _dx = 0;
    _dy = 0;
    _accepted = false;
    _ended = false;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _dx += event.delta.dx;
      _dy += event.delta.dy;

      if (!_accepted &&
          _dx.abs() > slop &&
          _dx.abs() > _dy.abs() * ratio) {
        // 先问宿主这一行是否参与选择（「..」行不参与）。
        // 不参与时直接让出，让列表正常滚动。
        if (!onStart(_downPosition)) {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
          return;
        }
        _accepted = true;
        resolve(GestureDisposition.accepted);
      }
      if (_accepted) onUpdate(event.position);
      return;
    }

    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _finish();
      stopTrackingPointer(event.pointer);
    }
  }

  void _finish() {
    if (_ended) return;
    _ended = true;
    if (_accepted) onEnd();
    _accepted = false;
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    // 手势被别处拒绝（例如长按胜出）时也要收尾，避免状态卡住
    _finish();
  }
}
