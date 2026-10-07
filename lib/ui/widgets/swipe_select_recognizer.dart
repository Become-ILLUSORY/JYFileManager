// 横向滑动识别器（列表行的「滑动连选」）。
//
// 为什么不能用内置的 HorizontalDragGestureRecognizer：
//   1. 竞技场按命中测试顺序加入，**内层先注册、先处理事件**。ListView 的
//      纵向滚动识别器挂在 Scrollable 上，是行的祖先；横滑识别器必须挂在
//      **每一行内部**（比 Scrollable 更深）才抢得过它。
//   2. 内置识别器要求横向位移大于纵向才胜出，而「斜着扫过几行连选」的
//      纵向分量天然很大，会被列表滚动先一步赢走。
//
// 本识别器的判定：横向累计位移超过 [slop]（默认 10，小于列表滚动的
// kTouchSlop=18）且此时纵向位移还没到滚动阈值 —— 即「手指是横向起手的」。
// 一旦接受，手指后续的任意移动（含大幅纵向）都交给回调去扩展选区，
// 列表也不再滚动；纯纵向滚动时横向抖动达不到 slop，不会误触发。
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 横向位移阈值：取得比 kTouchSlop(18) 小，才能在列表滚动之前抢下
/// 「横向起手」的滑动。纯纵向滚动时横向抖动远小于该值。
const double kSwipeSelectSlop = 10;

class SwipeSelectRecognizer extends OneSequenceGestureRecognizer {
  SwipeSelectRecognizer({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.slop = kSwipeSelectSlop,
  });

  /// 手势被接受时回调，携带**按下时**的全局坐标（用于确定起始行）
  void Function(Offset global) onStart;

  /// 手指移动中回调，携带当前位置
  void Function(Offset global) onUpdate;

  /// 手势结束回调
  VoidCallback onEnd;

  /// 横向位移阈值
  final double slop;

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

      // 判定「横向起手」：横向已越过阈值，且当前横向位移大于纵向位移。
      // 后者保证垂直滚动（含快速上滑时的手抖）不会被抢走 —— 那种情况下
      // 纵向分量远大于横向。横向起手后再纵向移动则不受影响（此时已接受）。
      if (!_accepted && _dx.abs() > slop && _dx.abs() > _dy.abs()) {
        _accepted = true;
        // 赢下竞技场：列表的纵向滚动不会再把手指抢走，
        // 之后的纵向移动全部用于扩展选中区间。
        resolve(GestureDisposition.accepted);
        onStart(_downPosition);
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
