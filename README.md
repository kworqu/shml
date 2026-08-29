# SHML

A lightweight, indentation-based markup compiler written in D. SHML allows you to write HTML templates with clean syntax, reusable component classes, slots, variables, and string concatenation, compiling them into clean, structured HTML.

<!-- Badges (Compact) -->
[![Language: D](https://img.shields.io/badge/Language-D-red.svg?logo=d)](https://dlang.org/)
[![Status](https://img.shields.io/badge/Status-Active_Development-orange.svg)](#)
[![Build Tool](https://img.shields.io/badge/Build-DUB-brightgreen.svg)](https://dub.pm/)
[![Version](https://img.shields.io/badge/Version-0.1.0-blue.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](#)

## Features

- **Indentation-Based Syntax**: Write clean templates without closing tags.
- **Component Classes & Slots**: Define reusable elements (`class ComponentName(...)`) and populate custom slots (`@slotName`).
- **Variables & String Concatenation**: Embed variables (`$varName`) and concatenate text or inline elements using the `~` operator.
- **Built-in CLI Tooling**:
  - `build`: Compile single files or entire directories.
  - `run`: Instantly compile and preview in your default browser.
  - `watch`: File watcher with an integrated live HTTP server (`http://localhost:8080`).
  - `translate`: Direct-to-console HTML output.

---

## Installation & Building

### Prerequisites

- [D Compiler](https://dlang.org/download.html) (DMD, LDC, or GDC)
- [DUB](https://dub.pm/) (D's package manager)

### Build Project

Clone the repository and build using **DUB**:

```bash
git clone https://github.com/kworqu/shml.git
cd shml
dub build
```

The compiled binary will be available in the project folder (e.g., `./shml` or `shml.exe`).

---

## Usage & CLI Commands

```bash
shml <command> [path]
```

### Available Commands

| Command | Description | Example |
| :--- | :--- | :--- |
| `build [path]` | Builds specified file, or all `.shml` files if `.` is provided | `shml build index.shml` or `shml build .` |
| `run [path]` | Compiles SHML and opens the target file in your default browser | `shml run index.shml` |
| `watch [path]` | Watches target files for changes, rebuilds automatically, and serves on `http://localhost:8080` | `shml watch .` |
| `translate [path]`| Compiles SHML and outputs HTML directly to stdout (console) | `shml translate main.shml` |
| `about` | Displays compiler version information | `shml about` |

*Note: If `path` is omitted for single-file commands, it defaults to `index.shml`.*

---

## SHML Syntax Example

Here is an example demonstrating SHML syntax with classes, variables, inline tags, and multiline text.

### `index.shml`

```shml
class Card(title):
    div.card-header:
        h2: $title;
    div.card-body:
        $children;

html:
    head:
        title: "SHML Demo Page";
    body.theme-dark#main-body:
        h1: "Welcome to " ~ span!"SHML" ~ " Compiler!";
        
        &Card(title="My First Component"):
            p: @"This is passed inside the default slot/children block.
            And this is new line!";
```

### Compiled HTML Output

```html
<html>
    <head>
        <title>SHML Demo Page</title>
    </head>
    <body id="main-body" class="theme-dark">
        <h1>Welcome to <span>SHML</span> Compiler!</h1>
        <div class="Card">
            <div class="card-header">
                <h2>My First Component</h2>
            </div>
            <div class="card-body">
                <p>This is passed inside the default slot/children block.</p>
            </div>
        </div>
    </body>
</html>
```

---

## License

This project is distributed under the MIT license.
