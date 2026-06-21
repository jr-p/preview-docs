# Mermaid Samples

Use this file to verify that Markdown fenced code blocks with `mermaid` render as diagrams.

## Flowchart

```mermaid
flowchart TD
    A[Open Markdown file] --> B{Contains mermaid fence?}
    B -- Yes --> C[Render diagram]
    B -- No --> D[Render normal Markdown]
    C --> E[Preview complete]
    D --> E
```

## Sequence Diagram

```mermaid
sequenceDiagram
    participant User
    participant App
    participant WebView
    participant Mermaid

    User->>App: Open sample.md
    App->>WebView: Load rendered HTML
    WebView->>Mermaid: Run diagrams
    Mermaid-->>WebView: SVG output
    WebView-->>User: Show preview
```

## Class Diagram

```mermaid
classDiagram
    class PreviewWindowController {
        +openInCurrentWindow(url)
        +refresh()
    }
    class PreviewViewController {
        +loadFile()
        +setMarkdownViewMode(mode)
        -loadMarkdown()
    }
    class PreviewWebView

    PreviewWindowController --> PreviewViewController
    PreviewViewController --> PreviewWebView
```

## State Diagram

```mermaid
stateDiagram-v2
    [*] --> Preview
    Preview --> Source: Switch to Source
    Source --> Preview: Switch to Preview
    Source --> Dirty: Edit text
    Dirty --> Source: Save
    Dirty --> Preview: Discard changes
```

## Entity Relationship Diagram

```mermaid
erDiagram
    PROJECT ||--o{ DOCUMENT : contains
    DOCUMENT ||--o{ DIAGRAM : embeds
    DOCUMENT {
        string path
        string extension
        boolean editable
    }
    DIAGRAM {
        string type
        string source
    }
```

## User Journey

```mermaid
journey
    title Preview a Mermaid diagram
    section Open
      Pick a Markdown file: 5: User
      Load file contents: 4: App
    section Render
      Parse Markdown: 4: WebView
      Render Mermaid blocks: 5: Mermaid
    section Inspect
      Scroll preview: 5: User
      Switch to source: 4: User
```

## Gantt Chart

```mermaid
gantt
    title Markdown Preview Rendering
    dateFormat  YYYY-MM-DD
    section Renderer
    Parse Markdown       :done, parse, 2026-06-21, 1d
    Render Mermaid SVG   :active, mermaid, after parse, 1d
    Verify preview       :verify, after mermaid, 1d
```

## Pie Chart

```mermaid
pie showData
    title Preview Content Types
    "Markdown" : 45
    "Images" : 25
    "PDF" : 15
    "Source files" : 15
```

## Git Graph

```mermaid
gitGraph
    commit id: "initial"
    branch mermaid-preview
    checkout mermaid-preview
    commit id: "add renderer"
    commit id: "bundle mermaid"
    checkout main
    merge mermaid-preview
```

## Requirement Diagram

```mermaid
requirementDiagram
    requirement markdown_preview {
        id: 1
        text: Markdown files render as HTML
        risk: low
        verifymethod: test
    }

    functionalRequirement mermaid_diagrams {
        id: 2
        text: Mermaid fences render as diagrams
        risk: medium
        verifymethod: inspection
    }

    markdown_preview - contains -> mermaid_diagrams
```

## Mindmap

```mermaid
mindmap
  root((PreviewDocs))
    Markdown
      Preview
      Source
      Mermaid
    Files
      Images
      PDF
      HTML
    Sidebar
      Browse
      Rename
      Ignore rules
```
