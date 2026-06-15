# From omr_template_specs.dart
answerGridTop = 262.0
answerGridBottom = 800.0  # Line 82
answerGridHeight = answerGridBottom - answerGridTop  # 538

answerOptionIndicatorHeight = 14.0  # Line 92
answerGridFooterHeight = 30.0  # Line 94

answerGridContentHeight = answerGridHeight - answerOptionIndicatorHeight - answerGridFooterHeight
answerRowsTop = answerGridTop + answerOptionIndicatorHeight
answerRowsBottom = answerRowsTop + answerGridContentHeight

print("=== Dart OmrPageConstants Calculation ===")
print(f"answerGridTop = {answerGridTop}")
print(f"answerGridBottom = {answerGridBottom}")
print(f"answerGridHeight = {answerGridHeight}")
print()
print(f"answerOptionIndicatorHeight = {answerOptionIndicatorHeight}")
print(f"answerGridFooterHeight = {answerGridFooterHeight}")
print()
print(f"answerGridContentHeight = {answerGridHeight} - {answerOptionIndicatorHeight} - {answerGridFooterHeight} = {answerGridContentHeight}")
print(f"answerRowsTop = {answerGridTop} + {answerOptionIndicatorHeight} = {answerRowsTop}")
print(f"answerRowsBottom = {answerRowsTop} + {answerGridContentHeight} = {answerRowsBottom}")
print()
print("=== Scanner Kotlin Constants ===")
print("ANSWER_GRID_TOP = 276.0")
print("ANSWER_GRID_BOTTOM = 770.0")
print()
print("=== Comparison ===")
print(f"Dart answerRowsTop ({answerRowsTop}) vs Scanner ANSWER_GRID_TOP (276.0): {'MATCH' if answerRowsTop == 276.0 else 'MISMATCH'}")
print(f"Dart answerRowsBottom ({answerRowsBottom}) vs Scanner ANSWER_GRID_BOTTOM (770.0): {'MATCH' if answerRowsBottom == 770.0 else 'MISMATCH'}")

# Calibration marks check
calibrationY = 810.0
print()
print("=== Calibration Marks ===")
print(f"calibrationY = {calibrationY}")
print(f"This is {calibrationY - answerRowsBottom} points BELOW answerRowsBottom")
print(f"This is {calibrationY - 770.0} points BELOW scanner ANSWER_GRID_BOTTOM")
