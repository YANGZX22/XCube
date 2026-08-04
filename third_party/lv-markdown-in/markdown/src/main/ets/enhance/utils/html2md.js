// -------------------- htmlToMarkdown.js --------------------
export function htmlToMarkdown(html) {
    if (!html || typeof html !== 'string') {
        return '';
    }

    // -------------------- STEP 0: 保护内容 --------------------
    const codeBlocks = [];
    const inlineCodes = [];
    const angleTags = [];
    const inlineFonts = [];

    // 保护代码块
    html = html.replace(/<pre[^>]*>([\s\S]*?)<\/pre>/gi, (_, content) => {
        // 尝试匹配 <code class="language-xxx"> 内部内容
        const codeMatch = content.match(/<code(?:\s+class=["']language-([\w-]+)["'])?>([\s\S]*?)<\/code>/i);
        let codeText = '';
        let lang = '';
        if (codeMatch) {
            lang = codeMatch[1] || ''; // 语言
            codeText = codeMatch[2];
        } else {
            codeText = content; // 没有 <code> 标签就直接取 pre 内容
        }
        // 转义 HTML 实体
        codeText = codeText
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');

        // 保存到 codeBlocks 数组，方便后续还原或处理
        const idx = codeBlocks.push(codeText) - 1;
        // return `\`\`\` ${lang}\n__CODE_BLOCK_${idx}__\n\`\`\``;
        return `__CODE_BLOCK_${idx}__`;
    });

    // 保护行内代码
    html = html.replace(/<code>([\s\S]*?)<\/code>/gi, (_, c) => {
        const idx = inlineCodes.push(c) - 1;
        return `__INLINE_CODE_${idx}__`;
    });
    // 保护行内代码
    html = html.replace(/\`([\s\S]*?)\`/gi, (_, c) => {
        const idx = inlineCodes.push(c) - 1;
        return `__INLINE_CODE_${idx}__`;
    });

    // 保护尖括号示例内容，自动检测 `<...>` 内的文本，排除 HTML 标签
    html = html.replace(/`?&?lt;[^>]+&?gt;`?/gi, match => {
        const idx = angleTags.push(match.replace(/&lt;/g, '<').replace(/&gt;/g, '>')) - 1;
        return `__ANGLE_TAG_${idx}__`;
    });

    // 保护 <font> 内容，避免在通用 HTML -> Markdown 过程中被剥离
    html = html.replace(/<font\b[^>]*>[^<]*<\/font>/gi, match => {
        const idx = inlineFonts.push(match) - 1;
        return `__INLINE_FONT_${idx}__`;
    });

    // -------------------- STEP 1: HTML → Markdown --------------------
    const rules = [
        { regex: /<div>([\s\S]*?)<\/div>/gi, replace: '$1' },

        // 标题
        { regex: /<h1>([\s\S]*?)<\/h1>/gi, replace: '# $1\n\n' },
        { regex: /<h2>([\s\S]*?)<\/h2>/gi, replace: '## $1\n\n' },
        { regex: /<h3>([\s\S]*?)<\/h3>/gi, replace: '### $1\n\n' },
        { regex: /<h4>([\s\S]*?)<\/h4>/gi, replace: '#### $1\n\n' },
        { regex: /<h5>([\s\S]*?)<\/h5>/gi, replace: '##### $1\n\n' },
        { regex: /<h6>([\s\S]*?)<\/h6>/gi, replace: '###### $1\n\n' },

        // 粗体/斜体/删除
        { regex: /<strong>([\s\S]*?)<\/strong>/gi, replace: '**$1**' },
        { regex: /<b>([\s\S]*?)<\/b>/gi, replace: '**$1**' },
        { regex: /<em>([\s\S]*?)<\/em>/gi, replace: '*$1*' },
        { regex: /<i>([\s\S]*?)<\/i>/gi, replace: '*$1*' },
        { regex: /<del>([\s\S]*?)<\/del>/gi, replace: '~~$1~~' },

        // 链接
        { regex: /<a [^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi, replace: '[$2]($1)' },

        // 图片
        { regex: /<img [^>]*src="([^"]+)"[^>]*alt="([^"]*?)"[^>]*\/?>/gi, replace: '![$2]($1)' },

        // 块引用（支持任意深度嵌套，修复解析中断问题）
        {
            regex: /<blockquote>([\s\S]*?)<\/blockquote>/gi,
            replace: (_, content) => {
                // 栈用于追踪嵌套深度（初始为0，每进一层+1，出一层-1）
                let stack = [];
                // 按行分割内容，保留原始换行结构
                const lines = removeFirstEmptyItem(content.trim().split('\n'));
                const result = [];

                for (const line of lines) {
                    // 临时存储当前行处理结果
                    let processedLine = line.trim();
                    // 记录当前行的标签数量，避免重复处理
                    let openTags = (processedLine.match(/<blockquote>/gi) || []).length;
                    let closeTags = (processedLine.match(/<\/blockquote>/gi) || []).length;

                    // 处理开标签（入栈，增加深度）
                    for (let i = 0; i < openTags; i++) {
                        stack.push(1);
                    }

                    // 处理内容行（非空且不含标签的行才添加>）
                    if (processedLine && !/<\/?blockquote>/.test(processedLine)) {
                        // 当前深度 = 栈长度，生成对应数量的>
                        const prefix = '>'.repeat(stack.length + 1);
                        result.push(`${prefix} ${processedLine}`);
                    }

                    // 处理闭标签（出栈，减少深度）
                    for (let i = 0; i < closeTags; i++) {
                        stack.pop();
                    }
                }

                return result.join('\n') + '\n\n';
            }
        },

        // 表格解析
        {
            regex: /<table>([\s\S]*?)<\/table>/gi,
            replace: (_, tableContent) => {
                const rows = tableContent.replace(/<thead>/gi, '')
                    .replace(/<\/thead>/gi, '')
                    .replace(/<tbody>/gi, '')
                    .replace(/<\/tbody>/gi, '')
                    .split(/<tr>/gi)
                    // 先去除标签和空白后再过滤空行（解决首行空行问题）
                    .map(tr => tr.replace(/<\/tr>/gi, '').trim())
                    .filter(row => row !== ''); // 只保留非空行

                if (rows.length === 0) {
                    return '';
                }

                const mdRows = rows.map(row => {
                    const cells = row.split(/<t[dh][^>]*>/gi)
                        .filter(Boolean)
                        .map(cell => cell.replace(/<\/t[dh]>/gi, '').trim());
                    return `| ${cells.join(' | ')} |`;
                });

                // 添加表头分隔行
                if (mdRows.length > 1) {
                    const headerSep = mdRows[0].replace(/[^|]+/g, '---');
                    mdRows.splice(1, 0, headerSep);
                }

                return mdRows.join('\n') + '\n\n';
            }
        },

        // 列表
        {
            regex: /<ul>([\s\S]*?)<\/ul>/gi, replace: (_, c) =>
        c.replace(/<li>([\s\S]*?)<\/li>/gi, (_, li) => `- ${li.trim()}`).trim() + '\n\n'
        },
        {
            regex: /<ol>([\s\S]*?)<\/ol>/gi, replace: (_, c) => {
            let i = 1;
            return c.replace(/<li>([\s\S]*?)<\/li>/gi, (_, li) => `${i++}. ${li.trim()}`).trim() + '\n\n';
        }
        },

        // 换行 & 段落
        { regex: /<br\s*\/?>/gi, replace: '  \n' },
        { regex: /<\/p\s*>/gi, replace: '\n\n' },
        { regex: /<p[^>]*>/gi, replace: '' },

        // 移除剩余 HTML 标签
        { regex: /<[^>]+>/gi, replace: '' }
    ];

    rules.forEach(r => {
        html = html.replace(r.regex, r.replace);
    });


    // -------------------- STEP 2: 还原保护内容 --------------------
    html = html.replace(/__ANGLE_TAG_(\d+)__/g, (_, idx) => angleTags[idx]);
    html = html.replace(/__INLINE_FONT_(\d+)__/g, (_, idx) => inlineFonts[idx]);
    html = html.replace(/__CODE_BLOCK_(\d+)__/g, (_, idx) => (`\`\`\` ${codeBlocks[idx]}\`\`\``));
    html = html.replace(/__INLINE_CODE_(\d+)__/g, (_, idx) => `\`${inlineCodes[idx]}\``);
    html = html.replace(/  ```/g, "```");


    // -------------------- STEP 3: 清理多余空行 --------------------
    html = html.replace(/\n{3,}/g, '\n\n').trim();

    return html;
}

function removeFirstEmptyItem(arr) {
    // 复制原数组避免直接修改（可选）
    const newArr = [...arr];
    // 遍历找到首个空项的索引
    for (let i = 0; i < newArr.length; i++) {
        // 判断是否为空值（空字符串、null、undefined）
        if (newArr[i] === '' || newArr[i] === null || newArr[i] === undefined) {
            // 移除该索引的项
            newArr.splice(i, 1);
            // 只移除首个，找到后立即退出循环
            break;
        }
    }
    return newArr;
}
