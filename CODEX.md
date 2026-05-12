# CODEX.md - Scraper Documentation

## Maintenance & Scraping Strategy

The Claude.ai usage page is highly dynamic and frequently changes its DOM structure (tag names, class names, etc.). To handle this, the app uses a **label-centric** approach rather than a selector-centric one.

### How it Works
1.  **Label Search:** The scraper looks for specific text strings ("Current session", "All models", "Sonnet only", "Claude Design") in *all* common text elements (`p`, `div`, `span`).
2.  **Container Recovery:** Once a label is found, it traverses upwards to find the closest "row" container (usually a `flex-row` div) that contains both the label and its corresponding percentage/reset data.
3.  **Flexible Extraction:** Inside that container, it uses regex to find `X% used` and looks for any element containing the word "Reset" or time patterns.
4.  **Global Fallback:** If the labels cannot be matched (e.g., they changed to "Current Usage"), the scraper falls back to a document-wide search for all `% used` patterns to ensure basic functionality.

### Troubleshooting (When it breaks)
1.  **Click "Show Debug Info"** in the menu bar.
2.  **Inspect the `logs` array:** It will tell you exactly which labels were found and which containers failed.
3.  **Check `bodyText`:** The debug info includes the first 1000 characters of the page text. Check if the labels ("Current session", etc.) have changed.
4.  **Update `UsageService.swift`:**
    *   If labels changed, update the strings in `findRowData` calls.
    *   If percentages aren't being found, check the `percentMatch` regex.
    *   If the page isn't loading, check the `findHeading` logic (it currently looks for "usage limits").

### Validation Protocol
After any change to the scraper:
```bash
./install.sh
# Then check the "Show Debug Info" in the app to ensure all fields populate.
```
