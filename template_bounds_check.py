rows_top = 276.0
scanner_bottom = 770.0

templates = [
    ('30', 10, 49.4),
    ('40', 10, 49.4),
    ('50', 10, 49.4),
    ('60', 12, 41.1666666667),
    ('70', 14, 35.2857142857),
    ('80', 16, 30.875),
    ('90', 18, 27.4444444444),
    ('100', 20, 24.7),
]

print('=== Template Row Analysis ===')
print()
print('Dart answerRowsTop = 276.0')
print('Dart answerRowsBottom = 276.0 + 494.0 = 770.0')
print('Scanner ANSWER_GRID_BOTTOM = 770.0')
print()
print('Template | Rows | RowHeight | Last Row Center | Last Row Bottom | Status')
print('-' * 80)

for name, rows, rh in templates:
    last_row_idx = rows - 1
    last_row_center = rows_top + (last_row_idx * rh) + (rh / 2)
    last_row_bottom = rows_top + (rows * rh)
    
    if last_row_bottom <= scanner_bottom:
        status = 'OK'
    else:
        status = f'EXCEEDS by {last_row_bottom - scanner_bottom:.1f}pt'
    
    print(f'{name:>8} | {rows:>4} | {rh:>9.1f} | {last_row_center:>15.1f} | {last_row_bottom:>15.1f} | {status}')
