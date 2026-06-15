# Scan fixture images

Add anonymized photos of real printed OMR sheets here for regression testing.

## Naming

`sheet_01_all_a.jpg`, `sheet_02_double_mark.jpg`, etc.

## Expected answers file

Create `expected.json` alongside images when native fixture tests are added:

```json
{
  "sheet_01_all_a.jpg": {
    "answers": ["A", "A", "A"],
    "score": 3
  }
}
```

## Privacy

- Remove student names and IDs from photos before committing
- Do not commit sheets with real student data
