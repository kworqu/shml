import std.stdio;
import std.string;
import std.array;
import std.ascii;
import std.conv;
import std.file;
import std.process;

import std.socket;
import core.thread;
import std.datetime;


//// Shml compiler ////
////   by kworqu   ////

// ASR && Nodes

enum NodeType { Element, Text, Variable, ClassCall, SlotBlock }

class ASTNode {
    NodeType type;
    string tag;
    string id;                          
    string[] classes;                   
    string[string] attributes;          
    string[string] attrVars;            
    bool isSelfClosing = false;      
    bool isInline = false;   
    
    string textValue;                   
    string varName;                     
    string slotName;                    
    
    bool isClassDef = false;
    string className;
    string[] classParams;
    
    ASTNode[] children;

    this(NodeType type) {
        this.type = type;
    }
}


// Token.type


enum TokenType { 
    Indent, Tag, Dot, Hash, Colon, Semicolon, LParen, RParen, Equals, 
    Comma, String, AtString, At, Tilde, Exclamation, QuestionMark, Dollar, Ampersand, EOL 
}

// Token

struct Token {
    TokenType type;
    string value;
    size_t line;
    size_t column;
}

// Lexer

class Lexer {
    static Token[] tokenize(string input, ref bool hasErrors) {
        Token[] tokens;
        size_t cursor = 0;
        size_t lineNum = 1;
        size_t colNum = 1;
        bool startOfLine = true;
        int currentIndent = 0;
        string currentLineTag = "";

        while (cursor < input.length) {
            if (startOfLine) {
                currentIndent = 0;
                currentLineTag = "";
                while (cursor < input.length && (input[cursor] == ' ' || input[cursor] == '\t')) {
                    currentIndent += (input[cursor] == '\t') ? 4 : 1;
                    cursor++; colNum++;
                }
                
                if (cursor < input.length && (input[cursor] == '\n' || input[cursor] == '\r')) {
                } else {
                    tokens ~= Token(TokenType.Indent, to!string(currentIndent), lineNum, 1);
                }
                startOfLine = false;
            }

            if (cursor >= input.length) break;
            char c = input[cursor];

            if (c == '\n' || c == '\r') {
                if (c == '\r' && cursor + 1 < input.length && input[cursor+1] == '\n') cursor++;
                tokens ~= Token(TokenType.EOL, "", lineNum, colNum);
                lineNum++; colNum = 1; cursor++;
                startOfLine = true;
                continue;
            }

            if (c == ' ' || c == '\t') { cursor++; colNum++; continue; }

            if (c == '/' && cursor + 1 < input.length && input[cursor+1] == '/') {
                while (cursor < input.length && input[cursor] != '\n' && input[cursor] != '\r') cursor++;
                continue;
            }

            size_t col = colNum;

            if (c == '.') { tokens ~= Token(TokenType.Dot, ".", lineNum, col); cursor++; colNum++; }
            else if (c == '#') { tokens ~= Token(TokenType.Hash, "#", lineNum, col); cursor++; colNum++; }
            else if (c == ':') { 
                tokens ~= Token(TokenType.Colon, ":", lineNum, col); 
                cursor++; colNum++;

                if (currentLineTag == "script" || currentLineTag == "style") {
                    size_t tempCursor = cursor;
                    size_t tempCol = colNum;
                    while (tempCursor < input.length && (input[tempCursor] == ' ' || input[tempCursor] == '\t')) {
                        tempCursor++;
                        tempCol++;
                    }

                    if (tempCursor < input.length && input[tempCursor] != '\n' && input[tempCursor] != '\r') {
                        cursor = tempCursor;
                        colNum = tempCol;
                        string rawVal = "";
                        size_t startCol = colNum;
                        while (cursor < input.length && input[cursor] != '\n' && input[cursor] != '\r') {
                            rawVal ~= input[cursor];
                            cursor++; colNum++;
                        }
                        tokens ~= Token(TokenType.String, rawVal, lineNum, startCol);
                    } else {
                        cursor = tempCursor;
                        colNum = tempCol;
                        if (cursor < input.length && input[cursor] == '\r') cursor++;
                        if (cursor < input.length && input[cursor] == '\n') cursor++;
                        
                        tokens ~= Token(TokenType.EOL, "", lineNum, colNum);
                        lineNum++; colNum = 1;
                        startOfLine = true;

                        int tagIndent = currentIndent;
                        string[] rawLines;
                        int baseIndent = -1;
                        size_t blockStartLine = lineNum;

                        while (cursor < input.length) {
                            size_t lineStartCur = cursor;
                            size_t lineStartLine = lineNum;

                            size_t scanCur = cursor;
                            int lineIndent = 0;
                            bool isEmpty = true;

                            while (scanCur < input.length && input[scanCur] != '\n' && input[scanCur] != '\r') {
                                if (input[scanCur] != ' ' && input[scanCur] != '\t') {
                                    isEmpty = false;
                                    break;
                                }
                                lineIndent += (input[scanCur] == '\t') ? 4 : 1;
                                scanCur++;
                            }

                            if (isEmpty) {
                                rawLines ~= "";
                                cursor = scanCur;
                                if (cursor < input.length && input[cursor] == '\r') cursor++;
                                if (cursor < input.length && input[cursor] == '\n') cursor++;
                                lineNum++; colNum = 1;
                            } else {
                                if (lineIndent > tagIndent) {
                                    if (baseIndent == -1) baseIndent = lineIndent;
                                    
                                    size_t stripCur = lineStartCur;
                                    int strippedCols = 0;
                                    while (stripCur < input.length && strippedCols < baseIndent && 
                                           (input[stripCur] == ' ' || input[stripCur] == '\t')) {
                                        strippedCols += (input[stripCur] == '\t') ? 4 : 1;
                                        stripCur++;
                                    }

                                    string lineContent = "";
                                    while (stripCur < input.length && input[stripCur] != '\n' && input[stripCur] != '\r') {
                                        lineContent ~= input[stripCur];
                                        stripCur++;
                                    }

                                    rawLines ~= lineContent;
                                    cursor = stripCur;
                                    if (cursor < input.length && input[cursor] == '\r') cursor++;
                                    if (cursor < input.length && input[cursor] == '\n') cursor++;
                                    lineNum++; colNum = 1;
                                } else {
                                    cursor = lineStartCur;
                                    lineNum = lineStartLine;
                                    colNum = 1;
                                    break;
                                }
                            }
                        }

                        while (rawLines.length > 0 && rawLines[$ - 1].length == 0) {
                            rawLines.length--;
                        }

                        if (rawLines.length > 0) {
                            tokens ~= Token(TokenType.Indent, to!string(baseIndent > 0 ? baseIndent : tagIndent + 4), blockStartLine, 1);
                            tokens ~= Token(TokenType.String, rawLines.join("\n"), blockStartLine, 1);
                            tokens ~= Token(TokenType.EOL, "", lineNum > 1 ? lineNum - 1 : 1, 1);
                        }
                    }
                }
            }
            else if (c == ';') { tokens ~= Token(TokenType.Semicolon, ";", lineNum, col); cursor++; colNum++; }
            else if (c == '(') { tokens ~= Token(TokenType.LParen, "(", lineNum, col); cursor++; colNum++; }
            else if (c == ')') { tokens ~= Token(TokenType.RParen, ")", lineNum, col); cursor++; colNum++; }
            else if (c == '=') { tokens ~= Token(TokenType.Equals, "=", lineNum, col); cursor++; colNum++; }
            else if (c == ',') { tokens ~= Token(TokenType.Comma, ",", lineNum, col); cursor++; colNum++; }
            else if (c == '~') { tokens ~= Token(TokenType.Tilde, "~", lineNum, col); cursor++; colNum++; }
            else if (c == '!') { tokens ~= Token(TokenType.Exclamation, "!", lineNum, col); cursor++; colNum++; }
            else if (c == '?') { tokens ~= Token(TokenType.QuestionMark, "?", lineNum, col); cursor++; colNum++; }
            else if (c == '$') { tokens ~= Token(TokenType.Dollar, "$", lineNum, col); cursor++; colNum++; }
            else if (c == '&') { tokens ~= Token(TokenType.Ampersand, "&", lineNum, col); cursor++; colNum++; }
            
            else if (c == '"') {
                cursor++; colNum++;
                string strVal = "";
                bool closed = false;
                while (cursor < input.length) {
                    if (input[cursor] == '"') { closed = true; cursor++; colNum++; break; }
                    if (input[cursor] == '\\' && cursor + 1 < input.length) {
                        cursor++; colNum++;
                        if (input[cursor] == 'n') strVal ~= '\n';
                        else if (input[cursor] == 't') strVal ~= '\t';
                        else if (input[cursor] == '"') strVal ~= '"';
                        else strVal ~= input[cursor];
                    } else {
                        strVal ~= input[cursor];
                    }
                    cursor++; colNum++;
                }
                if (!closed) { printError(lineNum, col, "Unclosed string literal"); hasErrors = true; }
                tokens ~= Token(TokenType.String, strVal, lineNum, col);
            }
            
            else if (c == '@') {
                if (cursor + 1 < input.length && input[cursor+1] == '\'') {
                    cursor += 2; colNum += 2;
                    string strVal = "";
                    bool closed = false;
                    while (cursor < input.length) {
                        if (input[cursor] == '\'') { closed = true; cursor++; colNum++; break; }
                        if (input[cursor] == '\n') { lineNum++; colNum = 1; strVal ~= '\n'; } 
                        else if (input[cursor] != '\r') { strVal ~= input[cursor]; colNum++; }
                        cursor++;
                    }
                    if (!closed) { printError(lineNum, col, "Unclosed multiline string"); hasErrors = true; }
                    tokens ~= Token(TokenType.AtString, strVal, lineNum, col);
                } else {
                    tokens ~= Token(TokenType.At, "@", lineNum, col); 
                    cursor++; colNum++;
                }
            }
            
            else if (isAlphaNum(c) || c == '_' || c == '-') {
                string ident = "";
                while (cursor < input.length && (isAlphaNum(input[cursor]) || input[cursor] == '_' || input[cursor] == '-')) {
                    ident ~= input[cursor];
                    cursor++; colNum++;
                }
                if (currentLineTag == "") {
                    currentLineTag = ident;
                }
                tokens ~= Token(TokenType.Tag, ident, lineNum, col);
            } else {
                cursor++; colNum++;
            }
        }
        
        if (!startOfLine) tokens ~= Token(TokenType.EOL, "", lineNum, colNum);
        return tokens;
    }
}

void printError(size_t line, size_t col, string msg) {
    writefln("\033[1;31m[!] %d:%d error: %s\033[0m", line, col, msg);
}

void printErrorClear(string msg) {
    writefln("\033[1;31m[!] Error: %s\033[0m", msg);
}


// Parser


class Parser {
    private Token[] tokens;
    private size_t pos = 0;
    public bool hasErrors = false;

    this(Token[] tokens) {
        this.tokens = tokens;
    }

    private Token peek() {
        if (pos < tokens.length) return tokens[pos];
        return Token(TokenType.EOL, "", 0, 0);
    }

    private Token consume() {
        Token t = peek();
        if (pos < tokens.length) pos++;
        return t;
    }

    ASTNode parseProgram() {
        ASTNode root = new ASTNode(NodeType.Element);
        root.tag = "root";

        ASTNode[] stack = [root];
        int[] indents = [-1];

        while (pos < tokens.length) {
            if (peek().type != TokenType.Indent) { pos++; continue; }

            Token indentTok = consume();
            int indent = to!int(indentTok.value);

            if (peek().type != TokenType.Tag && peek().type != TokenType.Ampersand && 
                peek().type != TokenType.At && peek().type != TokenType.Dollar &&
                peek().type != TokenType.String && peek().type != TokenType.AtString) {
                while (pos < tokens.length && peek().type != TokenType.EOL) pos++;
                continue;
            }

            ASTNode node = parseLineNode(indent);
            if (node is null) {
                while (pos < tokens.length && peek().type != TokenType.EOL) pos++;
                if (pos < tokens.length) pos++;
                continue;
            }

            while (stack.length > 1 && indent <= indents[$ - 1]) {
                stack.length--; indents.length--;
            }

            stack[$ - 1].children ~= node;

            bool canAcceptBlockChildren = node.isClassDef || 
                                          node.type == NodeType.ClassCall || 
                                          node.type == NodeType.SlotBlock || 
                                          (!node.isSelfClosing && node.type == NodeType.Element);

            if (canAcceptBlockChildren) {
                stack ~= node;
                indents ~= indent;
            }

            if (peek().type == TokenType.EOL) pos++;
        }

        return root;
    }

    private ASTNode parseLineNode(int currentIndent) {
        if (peek().type == TokenType.String || peek().type == TokenType.AtString) {
            Token strTok = consume();
            ASTNode node = new ASTNode(NodeType.Text);
            node.textValue = strTok.value;
            if (peek().type == TokenType.Semicolon) consume();
            return node;
        }

        if (peek().type == TokenType.Ampersand) {
            consume();
            ASTNode node = new ASTNode(NodeType.ClassCall);
            node.className = consume().value;
            if (peek().type == TokenType.LParen) {
                consume();
                parseAttributes(node);
            }
            if (peek().type == TokenType.Semicolon) consume();
            return node;
        }

        if (peek().type == TokenType.At) {
            consume();
            ASTNode node = new ASTNode(NodeType.SlotBlock);
            if (peek().type == TokenType.Tag) {
                node.slotName = consume().value;
            } else {
                printError(peek().line, peek().column, "Expected slot name after @");
                hasErrors = true; return null;
            }
            if (peek().type == TokenType.Colon) {
                consume();
                if (peek().type != TokenType.EOL) {
                    if (!parseConcatExpression(node, currentIndent)) return null;
                }
            }
            return node;
        }

        if (peek().type == TokenType.Dollar) {
            consume();
            ASTNode node = new ASTNode(NodeType.Variable);
            if (peek().type == TokenType.Tag) {
                node.varName = consume().value;
                while (peek().type == TokenType.Dot) {
                    consume();
                    if (peek().type == TokenType.Tag) node.varName ~= "." ~ consume().value;
                }
            } else {
                printError(peek().line, peek().column, "Expected variable name after $");
                hasErrors = true; return null;
            }
            if (peek().type == TokenType.Semicolon) consume();
            return node;
        }

        Token tagTok = consume();

        if (tagTok.value == "component") {
            ASTNode node = new ASTNode(NodeType.Element);
            node.isClassDef = true;
            node.className = consume().value;
            
            if (peek().type == TokenType.LParen) {
                consume();
                while (peek().type != TokenType.RParen && peek().type != TokenType.EOL) {
                    if (peek().type == TokenType.Tag) {
                        node.classParams ~= consume().value;
                    }
                    if (peek().type == TokenType.Comma) consume();
                }
                if (peek().type == TokenType.RParen) consume();
            }
            if (peek().type == TokenType.Colon) consume();
            return node;
        }

        ASTNode node = new ASTNode(NodeType.Element);
        node.tag = tagTok.value;

        while (peek().type == TokenType.Dot || peek().type == TokenType.Hash) {
            Token modTok = consume();
            if (peek().type == TokenType.Tag) {
                if (modTok.type == TokenType.Dot) node.classes ~= consume().value;
                else node.id = consume().value;
            } else {
                printError(peek().line, peek().column, "Expected identifier");
                hasErrors = true; return null;
            }
        }

        if (peek().type == TokenType.LParen) {
            consume();
            parseAttributes(node);
        }

        if (peek().type == TokenType.Semicolon) {
            consume();
            node.isSelfClosing = true;
            return node;
        }

        if (peek().type == TokenType.Colon) {
            consume();
            if (peek().type != TokenType.EOL) {
                if (!parseConcatExpression(node, currentIndent)) return null;
            }
        }

        return node;
    }

    private ASTNode parseSingleInlineNode(int baseIndent) {
        Token current = peek();
        
        if (current.type == TokenType.String || current.type == TokenType.AtString) {
            consume();
            ASTNode textNode = new ASTNode(NodeType.Text);
            textNode.textValue = (current.type == TokenType.AtString) 
                ? stripMultilineIndent(current.value, baseIndent) : current.value;
            return textNode;
        } 
        else if (current.type == TokenType.Dollar) {
            consume(); 
            string vName = consume().value;
            while (peek().type == TokenType.Dot) {
                consume();
                if (peek().type == TokenType.Tag) vName ~= "." ~ consume().value;
            }
            ASTNode varNode = new ASTNode(NodeType.Variable);
            varNode.varName = vName;
            return varNode;
        }
        else if (current.type == TokenType.Tag) {
            Token inlineTagTok = consume();
            
            ASTNode inlineNode = new ASTNode(NodeType.Element);
            inlineNode.tag = inlineTagTok.value;
            inlineNode.isInline = true;
            
            while (peek().type == TokenType.Dot || peek().type == TokenType.Hash) {
                Token modTok = consume();
                if (peek().type == TokenType.Tag) {
                    if (modTok.type == TokenType.Dot) inlineNode.classes ~= consume().value;
                    else inlineNode.id = consume().value;
                } else {
                    printError(peek().line, peek().column, "Expected identifier after . or #");
                    hasErrors = true; return null;
                }
            }
            
            if (peek().type == TokenType.Exclamation) {
                consume();
                if (peek().type == TokenType.LParen) {
                    consume();
                    parseInlineArguments(inlineNode, baseIndent);
                } else {
                    printError(peek().line, peek().column, "Expected '(' after '!' for inline tag");
                    hasErrors = true; return null;
                }
            } else if (peek().type == TokenType.QuestionMark) {
                consume();
                inlineNode.isSelfClosing = true;
                if (peek().type == TokenType.LParen) {
                    consume();
                    parseAttributes(inlineNode);
                }
            } else {
                printError(inlineTagTok.line, inlineTagTok.column, "Expected '!' or '?' after inline tag");
                hasErrors = true; return null;
            }
            return inlineNode;
        }
        else if (current.type == TokenType.Ampersand) {
            consume();
            if (peek().type != TokenType.Tag) {
                printError(peek().line, peek().column, "Expected component name after &");
                hasErrors = true; return null;
            }
            Token compTok = consume();
            
            ASTNode compNode = new ASTNode(NodeType.ClassCall);
            compNode.className = compTok.value;
            compNode.isInline = true;
            
            if (peek().type == TokenType.Exclamation) {
                consume();
                if (peek().type == TokenType.LParen) {
                    consume();
                    parseInlineArguments(compNode, baseIndent);
                } else {
                    printError(peek().line, peek().column, "Expected '(' after '!' for inline component");
                    hasErrors = true; return null;
                }
            } else if (peek().type == TokenType.QuestionMark) {
                consume();
                compNode.isSelfClosing = true;
                if (peek().type == TokenType.LParen) {
                    consume();
                    parseAttributes(compNode);
                }
            } else if (peek().type == TokenType.LParen) {
                consume();
                parseAttributes(compNode);
            }
            return compNode;
        }
        
        return null;
    }

    private void parseInlineArguments(ASTNode node, int baseIndent) {
        Token pt = peek();
        bool isBody = false;
        
        if (pt.type == TokenType.String || pt.type == TokenType.AtString || 
            pt.type == TokenType.Dollar || pt.type == TokenType.Ampersand) {
            isBody = true;
        } else if (pt.type == TokenType.Tag) {
            size_t lookahead = pos;
            bool foundBang = false;
            while (lookahead < tokens.length) {
                TokenType lt = tokens[lookahead].type;
                if (lt == TokenType.Exclamation || lt == TokenType.QuestionMark) { foundBang = true; break; }
                if (lt == TokenType.Equals || lt == TokenType.Comma || lt == TokenType.RParen) { break; }
                lookahead++;
            }
            if (foundBang) isBody = true;
        }
        
        if (isBody) {
            bool expectingOperator = false;
            while (pos < tokens.length && peek().type != TokenType.Comma && peek().type != TokenType.RParen) {
                Token current = peek();
                if (current.type == TokenType.String || current.type == TokenType.AtString || 
                    current.type == TokenType.Tag || current.type == TokenType.Dollar || 
                    current.type == TokenType.Ampersand) {
                    
                    if (expectingOperator) {
                        printError(current.line, current.column, "Missing '~' operator");
                        hasErrors = true; break;
                    }
                    
                    ASTNode bNode = parseSingleInlineNode(baseIndent);
                    if (bNode !is null) node.children ~= bNode;
                    expectingOperator = true;
                    
                } else if (current.type == TokenType.Tilde) {
                    if (!expectingOperator) {
                        printError(current.line, current.column, "Unexpected '~' operator");
                        hasErrors = true; break;
                    }
                    consume();
                    expectingOperator = false;
                } else {
                    break;
                }
            }
            if (peek().type == TokenType.Comma) consume();
        }
        
        parseAttributes(node);
    }

    private void parseAttributes(ASTNode node) {
        while (peek().type != TokenType.RParen && peek().type != TokenType.EOL) {
            if (peek().type == TokenType.Tag) {
                string attrName = consume().value;
                if (peek().type == TokenType.Equals) {
                    consume();
                    Token valTok = consume();
                    if (valTok.type == TokenType.String || valTok.type == TokenType.AtString) {
                        node.attributes[attrName] = valTok.value;
                    } else if (valTok.type == TokenType.Dollar) {
                        consume();
                        string vName = consume().value;
                        while (peek().type == TokenType.Dot) {
                            consume();
                            if (peek().type == TokenType.Tag) vName ~= "." ~ consume().value;
                        }
                        node.attrVars[attrName] = vName;
                    } else {
                        printError(valTok.line, valTok.column, "Expected string or variable for attribute");
                        hasErrors = true;
                    }
                } else {
                    node.attributes[attrName] = ""; 
                }
            } else {
                Token errTok = consume();
                if (errTok.type != TokenType.Comma) {
                    printError(errTok.line, errTok.column, "Expected attribute name");
                    hasErrors = true;
                }
                continue;
            }
            
            if (peek().type == TokenType.Comma) consume();
        }
        
        if (peek().type == TokenType.RParen) consume(); 
        else {
            printError(peek().line, peek().column, "Expected ')' closing attributes");
            hasErrors = true;
        }
    }

    private bool parseConcatExpression(ASTNode parent, int baseIndent) {
        bool expectingOperator = false;

        while (pos < tokens.length && peek().type != TokenType.EOL && peek().type != TokenType.Semicolon) {
            Token current = peek();

            if (current.type == TokenType.String || current.type == TokenType.AtString || 
                current.type == TokenType.Tag || current.type == TokenType.Dollar || 
                current.type == TokenType.Ampersand) {
                
                if (expectingOperator) {
                    printError(current.line, current.column, "Missing '~' operator");
                    hasErrors = true; return false;
                }

                ASTNode node = parseSingleInlineNode(baseIndent);
                if (node is null) return false;
                
                parent.children ~= node;
                expectingOperator = true;
                
            } else if (current.type == TokenType.Tilde) {
                if (!expectingOperator) {
                    printError(current.line, current.column, "Unexpected '~' operator");
                    hasErrors = true; return false;
                }
                consume();
                expectingOperator = false;
            } else {
                break;
            }
        }
        
        if (peek().type == TokenType.Semicolon) consume();

        if (!expectingOperator && parent.children.length > 0) {
            printError(peek().line, peek().column, "Trailing '~' operator");
            hasErrors = true; return false;
        }

        return true;
    }

    private string stripMultilineIndent(string raw, int baseIndent) {
        string[] lines = raw.splitLines();
        if (lines.length == 0) return "";
        string result = lines[0];
        
        foreach (i; 1 .. lines.length) {
            string l = lines[i];
            int spacesToStrip = baseIndent;
            size_t idx = 0;
            while (idx < l.length && spacesToStrip > 0) {
                if (l[idx] == ' ') { spacesToStrip--; idx++; }
                else if (l[idx] == '\t') { spacesToStrip -= 4; idx++; }
                else break;
            }
            result ~= "\n" ~ l[idx .. $];
        }
        return result;
    }
}


// Generator


class HtmlGenerator {
    static ASTNode[string] classDefs;

    static string generate(ASTNode node, int level = -1, string[string] vars = null, ASTNode[][string] slots = null) {
        if (node.tag == "root") {
            classDefs.clear();
            foreach (child; node.children) {
                if (child.isClassDef) {
                    classDefs[child.className] = child;
                }
            }
            string result = "";
            foreach (child; node.children) result ~= generate(child, 0, vars, null);
            return result;
        }

        if (node.isClassDef || node.type == NodeType.SlotBlock) return "";

        string indentStr = (level >= 0) ? replicate("    ", level) : "";

        if (node.type == NodeType.Text) {
            return indentStr ~ node.textValue ~ "\n";
        }

        if (node.type == NodeType.Variable) {
            if (node.varName == "children" && slots !is null && "children" in slots) {
                string res = "";
                foreach(c; slots["children"]) res ~= generate(c, level, vars, slots);
                return res;
            }
            if (node.varName.startsWith("slot.") && slots !is null) {
                string sName = node.varName[5..$];
                if (sName in slots) {
                    string res = "";
                    foreach(c; slots[sName]) res ~= generate(c, level, vars, slots);
                    return res;
                }
                return "";
            }
            string val = (node.varName in vars) ? vars[node.varName] : "";
            if (val.length > 0 && level >= 0) return indentStr ~ val ~ "\n";
            return val;
        }

        if (node.type == NodeType.ClassCall) {
            if (node.className !in classDefs) {
                printErrorClear("An unformed component was used: " ~ node.className);
                return indentStr ~ "<!-- Error: Component '" ~ node.className ~ "' not found -->\n";
            }
            
            ASTNode def = classDefs[node.className];
            string nl = (level >= 0) ? "\n" : "";
            string result = indentStr ~ "<div class=\"" ~ node.className ~ "\">" ~ nl;
            
            string[string] newVars;
            foreach(k, v; node.attributes) newVars[k] = v;
            foreach(k, varName; node.attrVars) newVars[k] = (varName in vars) ? vars[varName] : "";
            
            ASTNode[][string] newSlots;
            ASTNode[] defaultChildren;
            
            foreach (c; node.children) {
                if (c.type == NodeType.SlotBlock) {
                    newSlots[c.slotName] ~= c.children;
                } else {
                    defaultChildren ~= c;
                }
            }
            newSlots["children"] = defaultChildren;
            
            foreach(child; def.children) {
                result ~= generate(child, (level >= 0) ? level + 1 : -1, newVars, newSlots);
            }
            
            result ~= indentStr ~ "</div>" ~ nl;
            return result;
        }

        string htmlAttrs = buildAttributes(node, vars);

        if (node.isSelfClosing) {
            return indentStr ~ "<" ~ node.tag ~ htmlAttrs ~ " />\n";
        }

        bool isInlineContent = (node.children.length > 0) || (node.tag == "script" || node.tag == "style");
        foreach (child; node.children) {
            if ((child.type == NodeType.Element && !child.isInline) || 
                (child.type == NodeType.ClassCall && !child.isInline) || 
                child.type == NodeType.SlotBlock) {
                isInlineContent = false;
                break;
            }
            if (child.type == NodeType.Variable && (child.varName == "children" || child.varName.startsWith("slot."))) {
                isInlineContent = false;
                break;
            }
        }

        if (isInlineContent) {
            return indentStr ~ "<" ~ node.tag ~ htmlAttrs ~ ">" ~ renderChildrenInline(node, vars, slots) ~ "</" ~ node.tag ~ ">\n";
        } else {
            string result = indentStr ~ "<" ~ node.tag ~ htmlAttrs ~ ">\n";
            foreach (child; node.children) {
                result ~= generate(child, level + 1, vars, slots);
            }
            result ~= indentStr ~ "</" ~ node.tag ~ ">\n";
            return result;
        }
    }

    private static string renderChildrenInline(ASTNode node, string[string] vars, ASTNode[][string] slots) {
        string result = "";
        foreach (child; node.children) {
            if (child.type == NodeType.Text) {
                result ~= child.textValue;
            } else if (child.type == NodeType.Variable) {
                if (child.varName == "children" && slots !is null && "children" in slots) {
                    foreach(c; slots["children"]) result ~= generate(c, -1, vars, slots);
                } else if (child.varName.startsWith("slot.") && slots !is null) {
                    string sName = child.varName[5..$];
                    if (sName in slots) {
                        foreach(c; slots[sName]) result ~= generate(c, -1, vars, slots);
                    }
                } else {
                    result ~= (child.varName in vars) ? vars[child.varName] : "";
                }
            } else if (child.type == NodeType.Element) {
                string childAttrs = buildAttributes(child, vars);
                if (child.isSelfClosing) {
                    result ~= "<" ~ child.tag ~ childAttrs ~ " />";
                } else {
                    result ~= "<" ~ child.tag ~ childAttrs ~ ">" ~ renderChildrenInline(child, vars, slots) ~ "</" ~ child.tag ~ ">";
                }
            } else if (child.type == NodeType.ClassCall) {
                result ~= generate(child, -1, vars, slots);
            }
        }
        return result;
    }

    private static string buildAttributes(ASTNode node, string[string] vars) {
        string res = "";
        if (node.id.length > 0) res ~= ` id="` ~ node.id ~ `"`;
        if (node.classes.length > 0) res ~= ` class="` ~ node.classes.join(" ") ~ `"`;
        
        foreach (k, v; node.attributes) {
            if (v == "") res ~= " " ~ k;
            else res ~= " " ~ k ~ `="` ~ v ~ `"`;
        }
        foreach (k, varName; node.attrVars) {
            string v = (varName in vars) ? vars[varName] : "";
            res ~= " " ~ k ~ `="` ~ v ~ `"`;
        }
        return res;
    }
}


// CLI


void printHelp() {
    writeln("\033[1;36mSHML Sts Compiler CLI\033[0m");
    writeln("\033[1mUsage:\033[0m shml <command> [path]");
    writeln();
    writeln("\033[1mCommands:\033[0m");
    writeln("  \033[32mrun\033[0m [path]        Compiles SHML and opens the result in the default browser");
    writeln("  \033[32mbuild\033[0m [path]      Builds specified file, or all files if '.' is provided");
    writeln("  \033[32mwatch\033[0m [path]      Watches files for changes, rebuilds, and serves on http://localhost:8080");
    writeln("  \033[32mtranslate\033[0m [path]  Outputs compiled HTML to console without saving");
    writeln("  \033[32mabout\033[0m             Displays compiler version information");
}

string compileSource(string sourceCode, string fileName) {
    bool lexerErrors = false;
    auto tokens = Lexer.tokenize(sourceCode, lexerErrors);
    auto parser = new Parser(tokens);
    auto ast = parser.parseProgram();

    if (lexerErrors || parser.hasErrors) {
        writefln("\033[1;31mCompilation failed for file: %s\033[0m", fileName);
        return null;
    }

    return HtmlGenerator.generate(ast);
}

string processSingleFile(string filePath, bool saveToFile) {
    if (!exists(filePath)) {
        writefln("\033[1;31mError:\033[0m File '%s' not found.", filePath);
        return null;
    }

    string source = readText(filePath);
    string html = compileSource(source, filePath);

    if (html is null) return null;

    if (saveToFile) {
        string outPath = filePath.endsWith(".shml") ? filePath[0 .. $ - 5] ~ ".html" : filePath ~ ".html";
        std.file.write(outPath, html);
        writefln("\033[1;32m[+] Successfully compiled:\033[0m %s -> %s", filePath, outPath);
        return outPath;
    } else {
        writeln(html);
        return null;
    }
}

void processDirectory(string dirPath) {
    if (!exists(dirPath) || !isDir(dirPath)) {
        writefln("\033[1;31mError:\033[0m Directory '%s' not found.", dirPath);
        return;
    }

    foreach (string file; dirEntries(dirPath, SpanMode.breadth)) {
        if (isFile(file) && file.endsWith(".shml")) {
            processSingleFile(file, true);
        }
    }
}

void openInBrowser(string url) {
    version(Windows) {
        browse(url);
    } else version(OSX) {
        spawnShell("open " ~ url);
    } else version(Posix) {
        spawnShell("xdg-open " ~ url);
    }
}

SysTime[string] getFileModificationTimes(string targetPath) {
    SysTime[string] times;
    if (isFile(targetPath)) {
        times[targetPath] = timeLastModified(targetPath);
    } else if (isDir(targetPath)) {
        foreach (string file; dirEntries(targetPath, SpanMode.breadth)) {
            if (isFile(file) && file.endsWith(".shml")) {
                times[file] = timeLastModified(file);
            }
        }
    }
    return times;
}

void startLiveServer(ushort port) {
    auto server = new Socket(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
    server.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    server.bind(new InternetAddress("127.0.0.1", port));
    server.listen(10);

    while (true) {
        auto client = server.accept();
        char[1024] buffer;
        auto received = client.receive(buffer);
        
        if (received > 0) {
            string htmlContent = "";
            if (exists("index.html")) {
                htmlContent = readText("index.html");
            } else {
                htmlContent = "<html><body><h1>index.html not found</h1></body></html>";
            }

            string response = "HTTP/1.1 200 OK\r\n" ~
                             "Content-Type: text/html; charset=utf-8\r\n" ~
                             "Content-Length: " ~ to!string(htmlContent.length) ~ "\r\n" ~
                             "Connection: close\r\n\r\n" ~ htmlContent;
            
            client.send(response);
        }
        client.close();
    }
}

void watchAndServe(string targetPath) {
    if (targetPath == ".") {
        processDirectory(".");
    } else {
        processSingleFile(targetPath, true);
    }

    ushort port = 8080;
    writefln("\033[1;34m[*] Starting live server on http://localhost:%d\033[0m", port);
    
    auto serverThread = new Thread(() {
        startLiveServer(port);
    });
    serverThread.isDaemon = true;
    serverThread.start();

    openInBrowser("http://localhost:8080");

    writefln("\033[1;33m[*] Watching for changes in '%s'... (Press Ctrl+C to stop)\033[0m", targetPath);
    
    auto lastTimes = getFileModificationTimes(targetPath);

    while (true) {
        Thread.sleep(dur!"msecs"(500));
        auto currentTimes = getFileModificationTimes(targetPath);

        bool changed = false;
        foreach (file, time; currentTimes) {
            if (file !in lastTimes || lastTimes[file] != time) {
                writefln("\033[1;33m[!] Change detected in %s. Rebuilding...\033[0m", file);
                changed = true;
                break;
            }
        }

        if (changed) {
            if (targetPath == ".") {
                processDirectory(".");
            } else {
                processSingleFile(targetPath, true);
            }
            lastTimes = currentTimes;
        }
    }
}

void main(string[] args) {
    if (args.length < 2) {
        printHelp();
        return;
    }

    string command = args[1];
    string pathArg = (args.length > 2) ? args[2] : "index.shml";

    switch (command) {
        case "run":
            string fileToRun = (pathArg == ".") ? "index.shml" : pathArg;
            string compiledPath = processSingleFile(fileToRun, true);
            if (compiledPath !is null) {
                writefln("\033[1;34m[*] Opening %s in browser...\033[0m", compiledPath);
                openInBrowser(compiledPath);
            }
            break;

        case "build":
            if (pathArg == ".") {
                processDirectory(".");
            } else {
                processSingleFile(pathArg, true);
            }
            break;

        case "watch":
            watchAndServe(pathArg);
            break;

        case "translate":
            string fileToTranslate = (pathArg == ".") ? "index.shml" : pathArg;
            processSingleFile(fileToTranslate, false);
            break;

        case "about":
            writeln("\033[1;35mSHML Sts Compiler version 0.1.2\033[0m");
            break;

        default:
            writefln("\033[1;31mError:\033[0m Unknown command '%s'", command);
            writeln();
            printHelp();
            break;
    }
}