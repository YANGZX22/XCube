// 新增：递归深度控制工具函数
const RECURSION_MAX_DEPTH = 100; // 合理设置递归上限，避免栈溢出

/* -------------------- 公用工具 -------------------- */
function isEmptyLine(s) {
    return /^\s*$/.test(s || '');
}

function getCodeFenceStart(line) {
    // Chat models sometimes indent a later fenced block with four or more
    // spaces, tabs, NBSP or an ideographic space. Accept that indentation
    // leniently so a missed opening fence cannot make its closing fence wrap
    // all following prose. Backtick info strings may not contain a backtick.
    const match = (line || '').match(/^([\s\u200B\uFEFF]*)(`{3,}|~{3,})([^\r\n]*)$/);
    if (!match) {
        return null;
    }
    const marker = match[2];
    const info = (match[3] || '').trim();
    if (marker[0] === '`' && info.includes('`')) {
        return null;
    }
    const languageMatch = info.match(/^\S+/);
    return {
        marker: marker[0],
        length: marker.length,
        indent: match[1].length,
        lang: languageMatch ? languageMatch[0] : null
    };
}

function isCodeFenceClose(line, fence) {
    const match = (line || '').match(/^[\s\u200B\uFEFF]*(`+|~+)[\s\u200B\uFEFF]*$/);
    return !!match && match[1][0] === fence.marker && match[1].length >= fence.length;
}

function stripCodeFenceIndent(line, indent) {
    if (indent <= 0) {
        return line;
    }
    const leadingWhitespace =
        ((line || '').match(/^[\s\u200B\uFEFF]*/) || [''])[0].length;
    return line.slice(Math.min(indent, leadingWhitespace));
}

function toSpaceCount(s) {
    // 把开头的 \t 视作 4 spaces，返回空格数量
    // 同时处理普通空格(U+0020)和不间断空格(U+00A0)
    const tabsReplaced = s.replace(/\t/g, '    ');
    // 匹配所有类型的空格字符，包括普通空格和不间断空格
    const m = tabsReplaced.match(/^[\s\u00A0]*/);
    return m ? m[0].length : 0;
}

function isSetextHeadingEnabled(options) {
    return !!(options && typeof options === 'object' && options.setextHeading === true);
}

function getSetextHeadingLevel(line, nextLine, options) {
    if (!isSetextHeadingEnabled(options)) {
        return 0;
    }
    if (!nextLine || isEmptyLine(line)) {
        return 0;
    }
    const underline = nextLine.trim();
    if (/^=+$/.test(underline)) {
        return 1;
    }
    if (/^-+$/.test(underline)) {
        return 2;
    }
    return 0;
}

function isSetextHeading(line, nextLine, options) {
    return getSetextHeadingLevel(line, nextLine, options) > 0;
}

function createLatexNode(text, block) {
    return {
        type: 'latex',
        block,
        text,
        children: [{ type: 'text', text }]
    };
}

function createLatexParagraph(text) {
    return {
        type: 'paragraph',
        children: [createLatexNode(text, true)]
    };
}

function findUnescapedDelimiter(text, delimiter, fromIndex) {
    let index = text.indexOf(delimiter, fromIndex);
    while (index !== -1) {
        let slashCount = 0;
        for (let i = index - 1; i >= 0 && text[i] === '\\'; i--) {
            slashCount++;
        }
        if (slashCount % 2 === 0) {
            return index;
        }
        index = text.indexOf(delimiter, index + delimiter.length);
    }
    return -1;
}

function getLatexBlockDelimiter(line) {
    const trimmed = (line || '').trim();
    if (trimmed.startsWith('\\[')) {
        return { open: '\\[', close: '\\]' };
    }
    if (trimmed.startsWith('$$')) {
        return { open: '$$', close: '$$' };
    }
    return null;
}

function isLatexBlockStartLine(line) {
    const trimmed = (line || '').trim();
    const delimiter = getLatexBlockDelimiter(trimmed);
    if (!delimiter) {
        return false;
    }
    const firstContent = trimmed.slice(delimiter.open.length);
    if (firstContent.trim().length === 0) {
        return true;
    }
    const singleLineEnd = findUnescapedDelimiter(firstContent, delimiter.close, 0);
    return singleLineEnd !== -1 &&
        firstContent.slice(singleLineEnd + delimiter.close.length).trim() === '';
}

function parseLatexBlock(lines, start) {
    const firstLine = lines[start] || '';
    const trimmedFirst = firstLine.trim();
    const delimiter = getLatexBlockDelimiter(firstLine);
    if (!delimiter) {
        return null;
    }

    const firstContent = trimmedFirst.slice(delimiter.open.length);
    const singleLineEnd = findUnescapedDelimiter(firstContent, delimiter.close, 0);
    if (singleLineEnd !== -1 && firstContent.slice(singleLineEnd + delimiter.close.length).trim() === '') {
        return {
            node: createLatexParagraph(firstContent.slice(0, singleLineEnd)),
            index: start + 1
        };
    }
    if (firstContent.trim().length > 0) {
        return null;
    }

    const contentLines = [];

    let i = start + 1;
    while (i < lines.length) {
        const line = lines[i];
        const end = findUnescapedDelimiter(line, delimiter.close, 0);
        if (end !== -1 && line.slice(end + delimiter.close.length).trim() === '') {
            const beforeClose = line.slice(0, end);
            if (beforeClose.length > 0) {
                contentLines.push(beforeClose);
            }
            return {
                node: createLatexParagraph(contentLines.join('\n')),
                index: i + 1
            };
        }
        contentLines.push(line);
        i++;
    }

    return {
        node: { type: 'paragraph', children: [{ type: 'text', text: lines.slice(start).join('\n') }] },
        index: lines.length
    };
}


function withRecursionLimit(fn) {
    return function (...args) {
        // 从参数中提取当前深度（默认 0），若无则初始化
        const hasDepthArg = typeof args[args.length - 1] === 'number';
        const currentDepth = hasDepthArg ? args[args.length - 1] : 0;
        if (currentDepth >= RECURSION_MAX_DEPTH) {
            console.warn(`递归深度超过上限 ${RECURSION_MAX_DEPTH}，已终止以避免栈溢出`);
            // 返回降级结果（普通文本节点），保证功能不中断
            if (typeof args[0] === 'string') {
                return [{ type: 'text', text: args[0] }];
            }
            return [];
        }
        // 传递深度+1 到下一层递归
        if (hasDepthArg) {
            args[args.length - 1] = currentDepth + 1;
            return fn(...args);
        }
        return fn(...args, currentDepth + 1);
    };
}

/* -------------------- 主解析入口（含脚注预扫描） -------------------- */
export function parseMarkdown(md, plugins, options) {
    let tableId = 0
    // 先把原始文本拆成行，预扫描脚注定义（[^id]: ... 多行）
    // Trim only empty outer lines. String.trim() also removes the leading
    // spaces from the first non-empty line, which changes fenced-code
    // indentation semantics.
    const rawLines = md.replace(/\r/g, '').split('\n');
    while (rawLines.length > 0 && isEmptyLine(rawLines[0])) {
        rawLines.shift();
    }
    while (rawLines.length > 0 && isEmptyLine(rawLines[rawLines.length - 1])) {
        rawLines.pop();
    }
    const footnoteDefs = {}; // id -> text (raw markdown)
    const consumed = new Set();

    for (let i = 0; i < rawLines.length; i++) {
        if (consumed.has(i)) {
            continue;
        }
        const line = rawLines[i];
        const m = line.match(/^\s*\[\^([^\]]+)\]:\s*(.*)$/);
        if (m) {
            const id = m[1];
            let content = m[2] || '';
            consumed.add(i);
            // 向下收集缩进行或空行（常见脚注多行用缩进或空行分段）
            let j = i + 1;
            while (j < rawLines.length) {
                if (consumed.has(j)) {
                    j++;
                    continue;
                }
                const next = rawLines[j];
                // 如果是下一个脚注定义，停止
                if (/^\s*\[\^([^\]]+)\]:/.test(next)) {
                    break;
                }
                // 如果是缩进行（起始空格或tab）或空行，视为脚注继续
                if (/^\s+/.test(next) || isEmptyLine(next)) {
                    content += '\n' + next.replace(/^\s{0,4}/, ''); // 去掉最多4个领先空格，保留相对缩进
                    consumed.add(j);
                    j++;
                    continue;
                }
                // 非缩进且非空行：结束脚注体
                break;
            }
            footnoteDefs[id] = content;
            // i 跳到 j-1 下个循环会 i++
            i = j - 1;
        }
    }

    // 重新组装未被 consumed 的行为新的 lines 用于主解析
    const lines = [];
    for (let idx = 0; idx < rawLines.length; idx++) {
        if (!consumed.has(idx)) {
            lines.push(rawLines[idx]);
        }
    }

    // 主解析（参考之前的逻辑，增强了列表与内联）
    const ast = [];
    let i = 0;
    while (i < lines.length) {
        const line = lines[i];

        if (isEmptyLine(line)) {
            i++;
            continue;
        }

        // 标题
        const h = line.match(/^(#{1,6})\s+(.*)$/);
        if (h) {
            ast.push({ type: 'heading', level: h[1].length, children: parseInline(h[2].trim(), plugins) });
            i++;
            continue;
        }

        const setextHeadingLevel = getSetextHeadingLevel(line, lines[i + 1], options);
        if (setextHeadingLevel > 0) {
            ast.push({ type: 'heading', level: setextHeadingLevel, children: parseInline(line.trim(), plugins) });
            i += 2;
            continue;
        }

        // 分割线
        if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) {
            ast.push({ type: 'hr' });
            i++;
            continue;
        }

        // 代码块(fenced)
        const codeFence = getCodeFenceStart(line);
        if (codeFence) {
            i++;
            const buf = [];
            while (i < lines.length && !isCodeFenceClose(lines[i], codeFence)) {
                buf.push(stripCodeFenceIndent(lines[i], codeFence.indent));
                i++;
            }
            const closed = i < lines.length && isCodeFenceClose(lines[i], codeFence);
            if (closed) {
                i++; // skip closing fence
            }
            ast.push({ type: 'codeBlock', lang: codeFence.lang, text: buf.join('\n'), closed });
            continue;
        }

        const latexBlock = parseLatexBlock(lines, i);
        if (latexBlock) {
            ast.push(latexBlock.node);
            i = latexBlock.index;
            continue;
        }

        // 表格（header + align）
        if (line.includes('|') && i + 1 < lines.length) {
            const align = parseTableAlignLine(lines[i + 1]);
            if (align) {
                const headerRaw = splitTableRowRespectingCode(lines[i]);
                i += 2;
                const colCount = headerRaw.length;
                const rowRawLines = [];

                let currentRow = null;

                while (i < lines.length && !isEmptyLine(lines[i])) {
                    const line = lines[i];
                    const trimmed = line.trim();

                    const isRowStart = trimmed.startsWith('|');

                    if (isRowStart) {
                        // 新的一行表格开始
                        if (currentRow) {
                            rowRawLines.push(currentRow);
                        }
                        currentRow = line;
                    } else {
                        // 只能是单元格内部换行
                        if (!currentRow) {
                            // 非法状态，直接终止表格解析
                            break;
                        }
                        currentRow += '\n' + line;
                    }

                    i++;
                }

                if (currentRow) {
                    rowRawLines.push(currentRow);
                }

                const headerCols = headerRaw.map((c) => c.trim());
                const rows = rowRawLines.map((raw) => splitTableRowRespectingCode(raw).map((c) => c.trim()));
                const headerNodes =
                    headerCols.map((h) => ({ type: 'tableCell', children: withRecursionLimit(parseMarkdown)(h, plugins, options) }));
                const rowNodes = rows.map((cols) => {
                    const cells = headerCols.map((_, idx) => {
                        const rawCell = (idx < cols.length) ? cols[idx] : '';
                        return { type: 'tableCell', children: withRecursionLimit(parseInline)(rawCell, plugins) };
                    });
                    if (cols.length > headerCols.length) {
                        for (let k = headerCols.length; k < cols.length; k++) {
                            cells.push({ type: 'tableCell', children: withRecursionLimit(parseInline)(cols[k], plugins) });
                        }
                    }
                    return { type: 'tableRow', children: cells };
                });
                ast.push({
                    tableId: tableId,
                    type: 'table',
                    header: headerNodes,
                    align,
                    rows: rowNodes
                });
                tableId = tableId + 1;
                continue;
            }
        }

        const blockPluginNode = matchBlockPlugin(line, plugins);
        if (blockPluginNode) {
            ast.push(blockPluginNode);
            i++;
            continue;
        }

        // 列表（支持嵌套）
        const listStartMatch = line.match(/^(\s*)([-*+]|(\d+)\.)\s+/);
        if (listStartMatch) {
            const result = parseList(lines, i, plugins, options);
            ast.push(result.node);
            i = result.index;
            continue;
        }

        // 引用块
        if (/^\s*>\s?/.test(line)) {
            const buf = [];
            while (i < lines.length && /^\s*>\s?/.test(lines[i])) {
                buf.push(lines[i].replace(/^\s*>\s?/, ''));
                i++;
            }
            ast.push({ type: 'blockquote', children: withRecursionLimit(parseMarkdown)(buf.join('\n'), plugins, options) });
            continue;
        }

        // 优化后
        let paraText = line; // 直接用字符串拼接，减少数组内存占用
        i++;
        while (i < lines.length && !isEmptyLine(lines[i]) &&
            !/^(#{1,6})\s+/.test(lines[i]) &&
            !/^\s*[-*_]{3,}\s*$/.test(lines[i]) &&
            !getCodeFenceStart(lines[i]) &&
            !/^\s*>/.test(lines[i]) &&
            !(lines[i].includes('|') && parseTableAlignLine(lines[i + 1] || '')) &&
            !matchBlockPlugin(lines[i], plugins) &&
            !isLatexBlockStartLine(lines[i]) &&
            !/^(\s*)([-*+]|(\d+)\.)\s+/.test(lines[i]) &&
            !isSetextHeading(lines[i], lines[i + 1], options)
        ) {
            paraText += '\n' + lines[i]; // 实时拼接，避免数组累积
            i++;
        }
        ast.push({ type: 'paragraph', children: parseInline(paraText.trim(), plugins) });
    }

    // 把脚注定义追加到 AST 末尾，格式： {type:'footnotes', children:[{id, children: ...}, ...]}
    const footnoteIds = Object.keys(footnoteDefs);
    if (footnoteIds.length > 0) {
        const fchildren = footnoteIds.map((id) => {
            const content = footnoteDefs[id];
            // 递归解析脚注内容（可能包含块级结构）
            return { id, children: withRecursionLimit(parseMarkdown)(content || '', plugins, options) };
        });
        ast.push({ type: 'footnotes', children: fchildren });
    }

    return ast;
}

/* -------------------- 列表解析（支持嵌套，输出规范化 children） -------------------- */
/**
 * parseList(lines, start) -> { node: listNode, index: nextIndex }
 * listNode: { type: 'ul'|'ol', children: [ listItem, ... ] }
 * listItem: { type: 'listItem', checked?: boolean, children: [blockNode, ...] }
 */
function parseList(lines, start, plugins, options) {
    let i = start;
    const firstMatch = lines[start].match(/^(\s*)([-*+]|(\d+)\.)\s+(.*)$/);
    const baseIndent = toSpaceCount(firstMatch[1]);
    const rootType = firstMatch[3] ? 'ol' : 'ul';
    const rootList = { type: rootType, children: [] };
    // stack: each item { indent, node } where node is a list node
    const stack = [{ indent: baseIndent, node: rootList }];

    while (i < lines.length) {
        const line = lines[i];
        if (isEmptyLine(line)) {
            // peek ahead: if next non-empty is list item -> consume blank and continue; else break
            let j = i + 1;
            while (j < lines.length && isEmptyLine(lines[j])) {
                j++;
            }
            // 若下一行是列表项，直接跳转到 j（避免逐行 i++）
            if (j < lines.length && /^(\s*)([-*+]|(\d+)\.)\s+/.test(lines[j])) {
                i = j;
                continue;
            } else {
                i = j; // 直接跳到非空行，减少循环
                break;
            }
        }

        const m = line.match(/^(\s*)([-*+]|(\d+)\.)\s+(.*)$/);
        if (!m) {
            // 非列表行，可能是当前最后一项的 continuation（如果缩进 > top indent）
            const leading = line.match(/^(\s*)/)[1];
            const leadCount = toSpaceCount(leading);
            const top = stack[stack.length - 1];
            let continuationStackIndex = top && leadCount > top.indent ? stack.length - 1 : -1;
            let latexBlock = null;
            let codeFenceBlock = null;
            if (continuationStackIndex === -1) {
                const fallbackStackIndex = findContinuationStackIndex(stack, leadCount);
                if (fallbackStackIndex !== -1) {
                    const fallbackTop = stack[fallbackStackIndex];
                    codeFenceBlock = collectIndentedCodeFence(lines, i, leading.length);
                    latexBlock = collectIndentedLatexBlock(lines, i, leading.length, fallbackTop.indent);
                    if (codeFenceBlock || latexBlock) {
                        continuationStackIndex = fallbackStackIndex;
                    }
                }
            }
            if (continuationStackIndex !== -1) {
                while (stack.length > continuationStackIndex + 1) {
                    stack.pop();
                }
                const top = stack[stack.length - 1];
                const parentList = top.node;
                const lastItem = parentList.children[parentList.children.length - 1];
                if (!lastItem) {
                    break;
                }
                if (!latexBlock) {
                    latexBlock = collectIndentedLatexBlock(lines, i, leading.length, top.indent);
                }
                if (!codeFenceBlock) {
                    codeFenceBlock = collectIndentedCodeFence(lines, i, leading.length);
                }
                if (codeFenceBlock) {
                    const blocks = withRecursionLimit(parseMarkdown)(codeFenceBlock.text, plugins, options);
                    if (!lastItem.children) {
                        lastItem.children = [];
                    }
                    lastItem.children.push(...blocks);
                    i = codeFenceBlock.index;
                    continue;
                }
                if (latexBlock) {
                    const blocks = withRecursionLimit(parseMarkdown)(latexBlock.text, plugins, options);
                    if (!lastItem.children) {
                        lastItem.children = [];
                    }
                    lastItem.children.push(...blocks);
                    i = latexBlock.index;
                    continue;
                }

                // 检查是否是表格的开始
                const trimmedLine = line.slice(Math.min(leading.length, line.length));
                if (trimmedLine.includes('|') && i + 1 < lines.length) {
                    // 尝试解析表格
                    const tableLines = [trimmedLine];
                    let j = i + 1;

                    // 收集表格的所有行
                    while (j < lines.length) {
                        const nextLine = lines[j];
                        const nextTrimmed = nextLine.slice(Math.min(leading.length, nextLine.length));

                        // 检查是否是表格行或空行
                        if (nextTrimmed.trim() === '' || (nextTrimmed.includes('|') || nextTrimmed.match(/^:?-+:?$/))) {
                            tableLines.push(nextTrimmed);
                            j++;
                        } else {
                            break;
                        }
                    }

                    // 检查是否有足够的行来构成表格
                    if (tableLines.length >= 2) {
                        // 解析表格
                        const tableMarkdown = tableLines.join('\n');
                        const tableBlocks = withRecursionLimit(parseMarkdown)(tableMarkdown, plugins, options);

                        if (tableBlocks.length > 0 && tableBlocks[0].type === 'table') {
                            // 表格解析成功，添加到列表项
                            if (!lastItem.children) {
                                lastItem.children = [];
                            }
                            lastItem.children.push(...tableBlocks);
                            i = j;
                            continue;
                        }
                    }
                }

                // 不是表格，按普通延续行处理
                const trimmed = line.slice(Math.min(leading.length, line.length));
                const blocks = withRecursionLimit(parseMarkdown)(trimmed, plugins, options);
                if (!lastItem.children) {
                    lastItem.children = [];
                }
                lastItem.children.push(...blocks);
                i++;
                continue;
            } else {
                break;
            }
        }

        const leading = m[1];
        const marker = m[2];
        const orderedNum = m[3];
        const rest = m[4];
        const indent = toSpaceCount(leading);
        const isOrdered = !!orderedNum;
        const listType = isOrdered ? 'ol' : 'ul';

        // 调整栈：若缩进小于栈顶则 pop
        while (stack.length > 0 && indent < stack[stack.length - 1].indent) {
            stack.pop();
        }

        // 如果缩进严格大于栈顶 -> 新嵌套列表
        if (indent && indent > stack[stack.length - 1].indent) {
            const parentList = stack[stack.length - 1].node;
            const prevItem = parentList.children[parentList.children.length - 1];
            // 如果没有 prevItem，视为同级（回退到同级）
            if (!prevItem) {
                // 创建一个同级项并继续（保证结构完整）
                const newItem =
                    { type: 'listItem', children: [{ type: 'paragraph', children: parseInline(rest.trim(), plugins) }] };
                parentList.children.push(newItem);
                i++;
                continue;
            } else {
                // 创建 nested list 并挂到 prevItem.children
                const newList = { type: listType, children: [] };
                if (!prevItem.children) {
                    prevItem.children = [];
                }
                prevItem.children.push(newList);
                stack.push({ indent, node: newList });
            }
        } else {
            // indent == stack top indent
            // 如果 marker type 与栈顶类型不一致，视为结束当前 list（由上层继续处理）
            if (listType !== stack[stack.length - 1]?.node?.type) {
                // 结束当前 list parsing，让调用者在主循环处理后续类型不同的 list
                break;
            }
        }

        const curList = stack[stack.length - 1].node;

        // 任务项检测
        const taskMatch = rest.match(/^\s*\[( |x|X)\]\s*(.*)$/);
        let listItem;
        if (taskMatch) {
            const checked = taskMatch[1].toLowerCase() === 'x';
            const content = taskMatch[2];
            listItem = {
                type: 'listItem',
                checked,
                children: [{ type: 'paragraph', children: parseInline(content, plugins) }]
            };
        } else {
            listItem = {
                type: 'listItem',
                children: [{ type: 'paragraph', children: parseInline(rest.trim(), plugins) }]
            };
        }

        curList.children.push(listItem);
        i++;

        // 吃掉紧接着的 continuation 行（缩进 > 当前 indent 且非新的 list item）
        while (i < lines.length) {
            if (isEmptyLine(lines[i])) {
                break;
            }
            const nextMatch = lines[i].match(/^(\s*)([-*+]|(\d+)\.)\s+/);
            const nextLeading = lines[i].match(/^(\s*)/)[1];
            const nextIndent = toSpaceCount(nextLeading);

            if (nextMatch) {
                // 新列表项，交由主循环处理（可能是嵌套、同级或回退）
                break;
            } else {
                if (nextIndent > indent) {
                    const codeFenceBlock = collectIndentedCodeFence(lines, i, nextLeading.length);
                    if (codeFenceBlock) {
                        const blocks = withRecursionLimit(parseMarkdown)(codeFenceBlock.text, plugins, options);
                        listItem.children.push(...blocks);
                        i = codeFenceBlock.index;
                        continue;
                    }
                    const latexBlock = collectIndentedLatexBlock(lines, i, nextLeading.length, indent);
                    if (latexBlock) {
                        const blocks = withRecursionLimit(parseMarkdown)(latexBlock.text, plugins, options);
                        listItem.children.push(...blocks);
                        i = latexBlock.index;
                        continue;
                    }

                    // 检查是否是表格的开始
                    const trimmedLine = lines[i].slice(Math.min(nextLeading.length, lines[i].length));
                    if (trimmedLine.includes('|') && i + 1 < lines.length) {
                        // 尝试解析表格
                        const tableLines = [trimmedLine];
                        let j = i + 1;

                        // 收集表格的所有行
                        while (j < lines.length) {
                            const nextLine = lines[j];
                            const nextTrimmed = nextLine.slice(Math.min(nextLeading.length, nextLine.length));

                            // 检查是否是表格行或空行
                            if (nextTrimmed.trim() === '' ||
                                (nextTrimmed.includes('|') || nextTrimmed.match(/^:?-+:?$/))) {
                                tableLines.push(nextTrimmed);
                                j++;
                            } else {
                                break;
                            }
                        }

                        // 检查是否有足够的行来构成表格
                        if (tableLines.length >= 2) {
                            // 解析表格
                            const tableMarkdown = tableLines.join('\n');
                            const tableBlocks = withRecursionLimit(parseMarkdown)(tableMarkdown, plugins, options);

                            if (tableBlocks.length > 0 && tableBlocks[0].type === 'table') {
                                // 表格解析成功，添加到列表项
                                listItem.children.push(...tableBlocks);
                                i = j;
                                continue;
                            }
                        }
                    }

                    // 不是表格，按普通延续行处理
                    const trimmed = lines[i].slice(Math.min(nextLeading.length, lines[i].length));
                    const blocks = withRecursionLimit(parseMarkdown)(trimmed, plugins, options);
                    listItem.children.push(...blocks);
                    i++;
                    continue;
                } else {
                    break;
                }
            }
        }
    }

    return { node: rootList, index: i };
}

function findContinuationStackIndex(stack, leadCount) {
    for (let i = stack.length - 2; i >= 0; i--) {
        if (leadCount > stack[i].indent) {
            const list = stack[i].node;
            if (list.children && list.children.length > 0) {
                return i;
            }
        }
    }
    return -1;
}

function getLeadingWhitespace(line) {
    const match = (line || '').match(/^(\s*)/);
    return match ? match[1] : '';
}

function stripContinuationIndent(line, stripLength) {
    const leading = getLeadingWhitespace(line);
    return line.slice(Math.min(stripLength, leading.length));
}

function collectIndentedCodeFence(lines, start, stripLength) {
    const firstLine = stripContinuationIndent(lines[start], stripLength);
    const fence = getCodeFenceStart(firstLine);
    if (!fence) {
        return null;
    }

    const blockLines = [firstLine];
    let i = start + 1;
    while (i < lines.length) {
        const normalizedLine = stripContinuationIndent(lines[i], stripLength);
        blockLines.push(normalizedLine);
        i++;
        if (isCodeFenceClose(normalizedLine, fence)) {
            break;
        }
    }
    return { text: blockLines.join('\n'), index: i };
}

function collectIndentedLatexBlock(lines, start, stripLength, parentIndent) {
    const firstLine = stripContinuationIndent(lines[start], stripLength);
    const delimiter = getLatexBlockDelimiter(firstLine);
    if (!delimiter) {
        return null;
    }

    const firstContent = firstLine.trim().slice(delimiter.open.length);
    const singleLineEnd = findUnescapedDelimiter(firstContent, delimiter.close, 0);
    if (singleLineEnd !== -1 &&
        firstContent.slice(singleLineEnd + delimiter.close.length).trim() === '') {
        return { text: firstLine, index: start + 1 };
    }
    if (firstContent.trim().length > 0) {
        return null;
    }

    const blockLines = [firstLine];
    let i = start + 1;
    while (i < lines.length) {
        const line = lines[i];
        if (!isEmptyLine(line)) {
            const leading = getLeadingWhitespace(line);
            const indent = toSpaceCount(leading);
            if (indent <= parentIndent) {
                return null;
            }
        }

        const strippedLine = isEmptyLine(line) ? '' : stripContinuationIndent(line, stripLength);
        blockLines.push(strippedLine);

        const end = findUnescapedDelimiter(strippedLine, delimiter.close, 0);
        if (end !== -1 && strippedLine.slice(end + delimiter.close.length).trim() === '') {
            return { text: blockLines.join('\n'), index: i + 1 };
        }
        i++;
    }

    return null;
}

/* -------------------- 表格相关工具 -------------------- */
/* 与之前实现一致，处理 inline code 内的 | 和转义 \| */
function splitTableRowRespectingCode(line) {
    const cols = [];
    const curChars = []; // 用数组收集字符，减少临时对象
    let inInlineCode = false;
    let backtickSeq = 0;
    for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '\\' && line[i + 1] === '|') {
            curChars.push('|'); // 数组 push 替代字符串拼接
            i++;
            continue;
        }
        if (ch === '`') {
            let j = i;
            while (j < line.length && line[j] === '`') {
                j++;
            }
            const seq = line.slice(i, j);
            curChars.push(seq); // 直接 push 子串，减少循环
            i = j - 1;
            continue;
        } else if (ch === '|' && !inInlineCode) {
            cols.push(curChars.join('')); // 一次性 join
            curChars.length = 0; // 清空数组，复用内存
        } else {
            curChars.push(ch);
        }
    }
    cols.push(curChars.join(''));
    const trimmed = cols.slice();
    if (line.trim().startsWith('|')) {
        if (trimmed.length && trimmed[0].trim() === '') {
            trimmed.shift();
        }
        if (trimmed.length && trimmed[trimmed.length - 1].trim() === '') {
            trimmed.pop();
        }
    }
    return trimmed;
}

function parseTableAlignLine(line) {
    const parts = splitTableRowRespectingCode(line).map((t) => t.trim());
    if (parts.length === 0) {
        return null;
    }
    const aligns = [];
    for (const p of parts) {
        if (!/^:?-+:?$/.test(p)) {
            return null;
        }
        const left = p.startsWith(':');
        const right = p.endsWith(':');
        if (left &&
            right) {
            aligns.push('center');
        } else if (left) {
            aligns.push('left');
        } else if (right) {
            aligns.push('right');
        } else {
            aligns.push('none');
        }
    }
    return aligns;
}

function createPluginRegExp(plugin) {
    try {
        return new RegExp(plugin.pattern, plugin.flags || '');
    } catch (_err) {
        return null;
    }
}

function buildPluginNode(plugin, match, raw) {
    const groups = [];
    for (let i = 1; i < match.length; i++) {
        if (typeof match[i] === 'string') {
            groups.push(match[i]);
        }
    }
    const params = match.groups ? Object.assign({}, match.groups) : undefined;
    return {
        type: 'plugin',
        pluginKey: plugin.key,
        display: plugin.display,
        raw,
        params,
        groups,
        copyText: raw,
        selectable: plugin.selectable !== false && plugin.display === 'inline'
    };
}

function matchBlockPlugin(line, plugins) {
    if (!plugins || plugins.length === 0) {
        return null;
    }
    const trimmedLine = (line || '').trim();
    if (!trimmedLine) {
        return null;
    }
    for (let i = 0; i < plugins.length; i++) {
        const plugin = plugins[i];
        if (!plugin || plugin.display !== 'block') {
            continue;
        }
        const regExp = createPluginRegExp(plugin);
        if (!regExp) {
            continue;
        }
        const match = regExp.exec(trimmedLine);
        if (!match || match.index !== 0) {
            continue;
        }
        if (plugin.matchMode === 'full-line' && match[0].length !== trimmedLine.length) {
            continue;
        }
        if (!match[0]) {
            continue;
        }
        return buildPluginNode(plugin, match, match[0]);
    }
    return null;
}

function matchInlinePlugin(text, startIdx, plugins) {
    if (!plugins || plugins.length === 0) {
        return null;
    }
    const source = text.slice(startIdx);
    for (let i = 0; i < plugins.length; i++) {
        const plugin = plugins[i];
        if (!plugin || plugin.display !== 'inline') {
            continue;
        }
        const regExp = createPluginRegExp(plugin);
        if (!regExp) {
            continue;
        }
        const match = regExp.exec(source);
        if (!match || match.index !== 0 || !match[0]) {
            continue;
        }
        return {
            node: buildPluginNode(plugin, match, match[0]),
            length: match[0].length
        };
    }
    return null;
}

/* -------------------- 内联解析：轻量 tokenizer（支持图片被链接包裹转为 image+href） -------------------- */

/**
 * Helper: 查找匹配的 ']'（支持嵌套中括号）
 */
function findMatchingBracket(text, startIdx) {
    // startIdx 指向 '['
    let depth = 0;
    for (let i = startIdx; i < text.length; i++) {
        if (text[i] === '[') {
            depth++;
        } else if (text[i] === ']') {
            depth--;
            if (depth === 0) {
                return i;
            }
        } else if (text[i] === '\\') {
            i++; // skip escaped char
        }
    }
    return -1;
}

/**
 * Helper: 在 '(' ... ')', 支持嵌套小括号，返回结束位置索引
 */
function findMatchingParen(text, startIdx) {
    // startIdx 指向 '('
    let depth = 0;
    for (let i = startIdx; i < text.length; i++) {
        if (text[i] === '(') {
            depth++;
        } else if (text[i] === ')') {
            depth--;
            if (depth === 0) {
                return i;
            }
        } else if (text[i] === '\\') {
            i++;
        }
    }
    return -1;
}

function parseInlineHtmlFont(text, startIdx) {
    const match = text.slice(startIdx).match(/^<\s*font\b([^>]*)>([^<]*)<\s*\/\s*font\s*>/i);
    if (!match) {
        return null;
    }

    const attrsText = match[1] || '';
    const innerText = decodeHtmlEntities(match[2] || '');
    const node = {
        type: 'inlineHtmlFont',
        text: innerText
    };

    const attrRegex = /(color|size|face)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))/gi;
    let attrMatch;
    while ((attrMatch = attrRegex.exec(attrsText)) !== null) {
        const key = attrMatch[1].toLowerCase();
        const rawValue = attrMatch[3] ?? attrMatch[4] ?? attrMatch[5] ?? '';
        const value = rawValue.trim();
        if (!value) {
            continue;
        }
        if (key === 'color') {
            node.color = value;
            continue;
        }
        if (key === 'face') {
            node.face = value;
            continue;
        }
        if (key === 'size') {
            const normalizedSize = normalizeInlineHtmlFontSize(value);
            if (normalizedSize !== undefined) {
                node.size = normalizedSize;
            }
        }
    }

    return {
        node,
        length: match[0].length
    };
}

function normalizeInlineHtmlFontSize(value) {
    if (!value) {
        return undefined;
    }

    const pxMatch = value.match(/^(\d+(?:\.\d+)?)px$/i);
    if (pxMatch) {
        return Number(pxMatch[1]);
    }

    const num = Number(value);
    if (Number.isNaN(num) || num <= 0) {
        return undefined;
    }

    // 兼容旧版 <font size="1-7"> 的字号映射规则
    if (/^\d+$/.test(value) && num >= 1 && num <= 7) {
        return 9 + (num - 1) * 3;
    }

    return num;
}

/**
 * parseInline: 将文本解析为内联节点数组
 * 支持：
 *  - inline code `...`
 *  - image ![alt](url "title") -> {type:'image', alt, url, title?}
 *  - link [text](url "title") -> {type:'link', url, title?, children: [...]}
 *      special-case: 如果 link 的 children 仅是 single image node -> 转为 image node 并附带 href
 *  - emphasis: ***bolditalic***, **bold**, *italic*
 *  - strikethrough: ~~text~~
 *  - footnote ref: [^id] -> {type:'footnoteRef', id}
 */
function parseInline(text, plugins) {
    if (text == null || text === '') {
        return [];
    }

    const nodes = [];
    let p = 0;
    while (p < text.length) {
        const ch = text[p];

        const inlinePluginResult = matchInlinePlugin(text, p, plugins);
        if (inlinePluginResult) {
            nodes.push(inlinePluginResult.node);
            p += inlinePluginResult.length;
            continue;
        }

        if (ch === '\n') {
            nodes.push({ type: 'lineBreak' });
            p++;
            continue;
        }

        if (ch === '<') {
            const fontResult = parseInlineHtmlFont(text, p);
            if (fontResult) {
                nodes.push(fontResult.node);
                p += fontResult.length;
                continue;
            }
        }

        // inline code: `...` (支持多个反引号作为分隔)
        if (ch === '`') {
            let j = p;
            while (j < text.length && text[j] === '`') {
                j++;
            }
            const backticks = text.slice(p, j);
            const end = text.indexOf(backticks, j);
            if (end !== -1) {
                const content = text.slice(j, end);
                nodes.push({ type: 'inlineCode', text: content });
                p = end + backticks.length;
                continue;
            } else {
                // 未闭合，作为普通文本
                nodes.push({ type: 'text', text: ch });
                p++;
                continue;
            }
        }

        // image: ![alt](url "title")
        if (ch === '!' && text[p + 1] === '[') {
            const open = p + 1;
            const close = findMatchingBracket(text, open);
            if (close !== -1) {
                const alt = text.slice(open + 1, close);
                let q = close + 1;
                while (q < text.length && /\s/.test(text[q])) {
                    q++;
                }
                if (text[q] === '(') {
                    const parenEnd = findMatchingParen(text, q);
                    if (parenEnd !== -1) {
                        let inside = text.slice(q + 1, parenEnd).trim();

                        let url = inside;
                        let title = "";
                        let width = undefined;
                        let height = undefined;

                        // 1️⃣ 提取 title（保持你原有逻辑）
                        const mTitle = inside.match(/\s+("([^"]*)"|'([^']*)')\s*$/);
                        if (mTitle) {
                            title = mTitle[2] !== undefined ? mTitle[2] : mTitle[3];
                            inside = inside.slice(0, mTitle.index).trim();
                        }

                        // 2️⃣ 提取宽高 =600x400 / =600x / =x400
                        const mSize = inside.match(/\s*=\s*(\d*)x(\d*)\s*$/);
                        if (mSize) {
                            width = mSize[1] ? Number(mSize[1]) : undefined;
                            height = mSize[2] ? Number(mSize[2]) : undefined;
                            inside = inside.slice(0, mSize.index).trim();
                        }

                        // 3️⃣ 剩下的就是纯 url
                        url = inside;

                        nodes.push({
                            type: 'image',
                            alt,
                            url,
                            title,
                            width,
                            height
                        });
                        p = parenEnd + 1;
                        continue;
                    }
                }
            }
            // fallback: treat as plain text
            nodes.push({ type: 'text', text: ch });
            p++;
            continue;
        }

        // link: [text](url "title") or reference-style not handled here
        if (ch === '[') {
            const close = findMatchingBracket(text, p);
            if (close !== -1) {
                const linkText = text.slice(p + 1, close);
                let q = close + 1;
                while (q < text.length && /\s/.test(text[q])) {
                    q++;
                }
                if (text[q] === '(') {
                    const parenEnd = findMatchingParen(text, q);
                    if (parenEnd !== -1) {
                        const inside = text.slice(q + 1, parenEnd).trim();
                        let url = inside;
                        let title;
                        const mTitle = inside.match(/\s+("([^"]*)"|'([^']*)')\s*$/);
                        if (mTitle) {
                            title = mTitle[2] !== undefined ? mTitle[2] : mTitle[3];
                            url = inside.slice(0, mTitle.index).trim();
                        }
                        // parse linkText recursively
                const children = withRecursionLimit(parseInline)(linkText, plugins);
                        // special-case: linkText 是单个 image 节点 -> 转换为 image 并附带 href
                        if (children.length === 1 && children[0].type === 'image') {
                            const img = Object.assign({}, children[0]);
                            img.href = url;
                            // 保留 title 优先级：如果 image 自身没有 title，用 link 的 title
                            if (!img.title && title) {
                                img.title = title;
                            }
                            nodes.push(img);
                        } else {
                            nodes.push({
                                type: 'link',
                                url,
                                title,
                                children
                            });
                        }
                        p = parenEnd + 1;
                        continue;
                    }
                }
                // 如果没有括号 URL，可能是简短的 [^id] 脚注引用
                const footRef = linkText.match(/^\^([^\]]+)$/);
                if (footRef) {
                    nodes.push({ type: 'footnoteRef', id: footRef[1] });
                    p = close + 1;
                    continue;
                }
            }
            // fallback -> plain text '['
            nodes.push({ type: 'text', text: ch });
            p++;
            continue;
        }

        // strikethrough: ~~...~~
        if (ch === '~' && text[p + 1] === '~') {
            const end = text.indexOf('~~', p + 2);
            if (end !== -1) {
                const inner = text.slice(p + 2, end);
                nodes.push({ type: 'strikethrough', children: parseInline(inner, plugins) });
                p = end + 2;
                continue;
            } else {
                nodes.push({ type: 'text', text: '~' });
                p++;
                continue;
            }
        }

        if (ch === '~') {
            nodes.push({ type: 'text', text: '~' });
            p++;
            continue;
        }

        // LaTeX delimiters: \(...\) and \[...\]
        if (ch === '\\') {
            const next = text[p + 1];
            if (next === '(' || next === '[') {
                const close = next === '(' ? '\\)' : '\\]';
                const end = text.indexOf(close, p + 2);
                if (end !== -1) {
                    const inner = text.slice(p + 2, end);
                    nodes.push(createLatexNode(inner, next === '['));
                    p = end + 2;
                    continue;
                }
            }
            nodes.push({ type: 'text', text: ch });
            p++;
            continue;
        }

        // emphasis/bold: lookahead for *** / ** / *
        // emphasis/bold with * 或 _
        if (ch === '*' || ch === '_') {
            let j = p;
            while (j < text.length && text[j] === ch) {
                j++;
            }
            const count = j - p;
            if (ch === '_' && isIntraWordUnderscore(text, p)) {
                nodes.push({ type: 'text', text: ch.repeat(count) });
                p = j;
                continue;
            }
            if (count >= 3) {
                const end = findEmphasisEnd(text, ch.repeat(3), p + 3);
                if (end !== -1) {
                    const inner = text.slice(p + 3, end);
                    nodes.push({ type: 'bolditalic', children: parseInline(inner, plugins) });
                    p = end + 3;
                    continue;
                }
            }
            if (count >= 2) {
                const end = findEmphasisEnd(text, ch.repeat(2), p + 2);
                if (end !== -1) {
                    const inner = text.slice(p + 2, end);
                    nodes.push({ type: 'bold', children: parseInline(inner, plugins) });
                    p = end + 2;
                    continue;
                }
            }
            const end = findEmphasisEnd(text, ch, p + 1);
            if (end !== -1) {
                const inner = text.slice(p + 1, end);
                nodes.push({ type: 'italic', children: parseInline(inner, plugins) });
                p = end + 1;
                continue;
            }
            nodes.push({ type: 'text', text: ch });
            p++;
            continue;
        }


        // 支持 $$...$$ 以及 $...$
        if (ch === '$') {
            // ---------- $$ 块级公式 ----------
            if (text[p + 1] === '$') {
                const end = text.indexOf('$$', p + 2);
                if (end !== -1) {
                    const inner = text.slice(p + 2, end);

                    // $$ 默认就是数学，不做金额判断
                    nodes.push(createLatexNode(inner, true));

                    p = end + 2;
                    continue;
                }

                // 不完整的 $$，退化成普通文本
                nodes.push({ type: 'text', text: '$$' });
                p += 2;
                continue;
            }

            const moneyPrefix = text.slice(p).match(/^\$\d{2,}(?:\.\d+)?(?:[kKmMbB])?/);
            if (moneyPrefix) {
                nodes.push({ type: 'text', text: moneyPrefix[0] });
                p += moneyPrefix[0].length;
                continue;
            }

            // ---------- $ 行内公式 ----------
            const end = text.indexOf('$', p + 1);
            if (end !== -1) {
                const inner = text.slice(p + 1, end);

                if (shouldParseInlineLatex(inner)) {
                    nodes.push(createLatexNode(inner, false));
                    p = end + 1;
                    continue;
                }
            }

            // 兜底：当普通字符 $
            nodes.push({ type: 'text', text: '$' });
            p++;
            continue;
        }


        // 检查是否是HTML实体
        const entityMatch = text.slice(p).match(/^&#(\d+);|&#x([0-9a-fA-F]+);/);
        if (entityMatch) {
            const entity = entityMatch[0];
            const decoded = decodeHtmlEntities(entity);
            nodes.push({ type: 'text', text: decoded });
            p += entity.length;
            continue;
        }

        // 检查是否是自动链接（http://或https://开头）
        const autoLinkMatch = text.slice(p).match(/^https?:\/\/[^\s\)!\?,;`]+/);
        if (autoLinkMatch) {
            const url = autoLinkMatch[0];
            nodes.push({
                type: 'link',
                url: url,
                title: '',
                children: [{ type: 'text', text: url }]
            });
            p += url.length;
            continue;
        }

        const plainTextMatch = text.slice(p).match(/^[^`$!\[\]\\~*_]+/);
        if (plainTextMatch) {
            const chunk = plainTextMatch[0];
            const decodedChunk = decodeHtmlEntities(chunk);
            nodes.push({ type: 'text', text: decodedChunk });
            p += chunk.length;
        } else {
            // 无匹配时，处理单个字符
            nodes.push({ type: 'text', text: text[p] });
            p++;
        }
    }

    // 合并相邻 text 节点
    const merged = [];
    for (const n of nodes) {
        if (n.type === 'text' && merged.length && merged[merged.length - 1].type === 'text') {
            merged[merged.length - 1].text += n.text;
        } else {
            merged.push(n);
        }
    }
    return merged;
}

function findEmphasisEnd(text, delimiter, fromIndex) {
    let end = text.indexOf(delimiter, fromIndex);
    while (end !== -1) {
        if (delimiter[0] !== '_' || !isIntraWordUnderscore(text, end)) {
            return end;
        }
        end = text.indexOf(delimiter, end + delimiter.length);
    }
    return -1;
}

function isIntraWordUnderscore(text, index) {
    return isUnicodeLetterOrNumber(text[index - 1]) && isUnicodeLetterOrNumber(text[index + 1]);
}

function isUnicodeLetterOrNumber(ch) {
    return !!ch && /[\p{L}\p{N}]/u.test(ch);
}

/**
 * 解析HTML实体，如 &#124; -> |, &#92; -> \
 */
function decodeHtmlEntities(text) {
    return text
        .replace(/&#(\d+);/g, (match, dec) => String.fromCharCode(dec))
        .replace(/&#x([0-9a-fA-F]+);/g, (match, hex) => String.fromCharCode(parseInt(hex, 16)));
}

function isLatexMath(content) {
    return (
        // LaTeX 命令
        /\\[a-zA-Z]+/.test(content) ||

            // 上下标（这是强数学信号）
        /[\^_]/.test(content) ||

            // 明确的等式
        /=/.test(content) ||

            // 常见数学运算符或比较符
        /[+\-*/<>≤≥≈≠]/.test(content) ||

            // 函数式结构：f(x), sin(x)
        /\w+\s*\(.+\)/.test(content)
    );
}

function shouldParseInlineLatex(content) {
    const inner = (content || '').trim();
    if (!inner || looksLikeMoney(inner) || looksLikeMoneyRange(inner)) {
        return false;
    }

    if (/[\u4e00-\u9fa5]/.test(inner) && !/\\[a-zA-Z]+/.test(inner)) {
        return false;
    }

    return isLatexMath(inner) || /^[a-zA-Z]$/.test(inner) || /^\d$/.test(inner);
}


function looksLikeMoney(content) {
    // 将 1 位数字视为数学表达式（如 $0$, $1$），避免被金额规则误判
    // 保留对常见金额写法的识别：$99 / $3800 / $100k
    return /^\d{2,}(\.\d+)?([kKmMbB])?$/.test(content);
}

function looksLikeMoneyRange(content) {
    // 3300 - 3400 / 3500-3600 / 1000 ~ 2000
    return /^\d+(\.\d+)?\s*[-~—]\s*\d+(\.\d+)?$/.test(content);
}
