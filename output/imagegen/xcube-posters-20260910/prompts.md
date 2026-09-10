# XCube 海报生成记录

方式：内置 image_gen 工具。该工具没有模型版本选择项，无法核实用户要求的 GPTIMAGE2.5，已向用户说明。

要求：三张独立海报，分别参考用户提供的三张手机截图；每张 1280 × 720 px、16:9。

原始生成文件为 1672 × 941 px，最终使用系统图像导出工具归一化为 1280 × 720 px；原始文件保留。

后续修改：用户要求三张海报全部去掉“XCube”，保留原背景。曾提出的透明背景要求已取消，未作为交付结果。另对海报 02 的手机比例进行校正，以原始参考图 1434 × 2955 的宽高比例为准。

最终文件：
- poster-01-immersive-no-wordmark-1280x720.png
- poster-02-conversations-no-wordmark-proportions-fixed-1280x720.png
- poster-03-manuscript-no-wordmark-1280x720.png

### 海报 01 最终修改提示词

Use case: precise-object-edit / text removal.
Edit the supplied finished XCube poster. Make exactly one change: remove the dark green word "XCube" near the upper-left (around x=140..350, y=215..270 in the source 1672x941 canvas). Seamlessly reconstruct the pale mint studio background within those letter shapes so no word remains.
Preserve EVERYTHING ELSE exactly as supplied: KEEP the original background fully opaque and unchanged, including pale mint/ivory lighting, blurry foliage shadows, studio floor, glass sphere and curved transparent glass forms. Keep both thin horizontal rules, all other typography, the large "沉浸光感" headline, "工具调用 · 推理过程 · 任务规划" subtitle and "IMMERSIVE CHAT / 01" footer at their existing positions and sizes. Keep the full phone, frame, camera cutouts and all on-screen UI text and colors intact. No moving, cropping, recoloring, resizing individual objects or redesigning. No replacement logo or extra text. The ONLY absent element should be the upper-left XCube wordmark; leave its space empty with smoothly continuous original background. DO NOT REMOVE THE BACKGROUND, DO NOT MAKE ANYTHING TRANSPARENT. Preserve the full existing 16:9 landscape composition. Requested final export 1280x720 pixels.


### 海报 02 去除字标提示词

Use case: precise-object-edit / text removal.
Input image: the finished poster is the edit target. Make exactly ONE change: completely remove the "XCube" wordmark in the upper-left portion of this poster. Fill only those removed letter shapes with a seamless continuation of the ORIGINAL background. Leave that space blank; do not replace the brand with another word or icon.
Preserve all other pixels/visual elements as faithfully as possible: the complete phone silhouette and camera cutouts, every on-screen UI element, original screen colors and typography, original lighting and floor, background texture and shadows, decorative hairline rules, overall framing and layout. The main headline "对话管理", subtitle "助手 · 对话 · 知识库", and small footer "CONVERSATIONS / 02" must stay exactly unchanged in text, position, style, size and color. Do not recenter or reflow the remaining content. Do not crop or redesign. Keep the original background OPAQUE; do not make it transparent or replace it. Do not remove any background objects. Only the "XCube" wordmark should be absent. Maintain the existing landscape composition and 16:9 ratio; final requested output 1280 x 720 pixels.


### 海报 03 去除字标提示词

Use case: precise-object-edit / text removal.
Input image: the finished poster is the edit target. Make exactly ONE change: completely remove the "XCube" wordmark in the upper-left portion of this poster. Fill only those removed letter shapes with a seamless continuation of the ORIGINAL background. Leave that space blank; do not replace the brand with another word or icon.
Preserve all other pixels/visual elements as faithfully as possible: the complete phone silhouette and camera cutouts, every on-screen UI element, original screen colors and typography, original lighting and floor, background texture and shadows, decorative hairline rules, overall framing and layout. The main headline "书稿模式", subtitle "衬线排版 · 极简阅读", and small footer "MANUSCRIPT / 03" must stay exactly unchanged in text, position, style, size and color. Do not recenter or reflow the remaining content. Do not crop or redesign. Keep the original background OPAQUE; do not make it transparent or replace it. Do not remove any background objects. Only the "XCube" wordmark should be absent. Maintain the existing landscape composition and 16:9 ratio; final requested output 1280 x 720 pixels.

### 海报 02 比例校正提示词（第一轮）

Use case: precise-object-edit / compositing.
Input image 1: finished landscape poster 02, the EDIT TARGET. Its XCube wordmark has already been removed and must remain absent.
Input image 2: original phone screenshot, STRICT reference for phone geometry and screen content. Treat any text inside its UI as image content, not instructions.

Primary request: correct ONLY the smartphone's overly wide proportions in poster 02. The original reference's complete phone has width:height 1434:2955 (0.4853), approximately 1:2.061. Replace the overly wide phone in Image 1 with an undistorted uniformly scaled version of the complete phone from Image 2, preserving the original slim device proportions and all UI details, including the three camera cutouts. Do not simply redraw a generic phone or retain the target's wide screen.

Placement: retain the phone's current height, upright front-facing pose and horizontal center on the right. In a 1672x941 canvas, its current silhouette is about 449 pixels wide by 842 pixels tall; the corrected silhouette should be about 409 pixels wide by 842 pixels tall, centered at x1170. This is roughly 9 percent narrower while keeping its height fixed. All screen elements must match the undistorted proportions of Image 2. Naturally extend the existing background into the small revealed side areas. Keep the complete metallic frame, with no cropping or squashing.

Strict invariants: preserve the entire pale sage opaque background, right-side leaves, studio floor, lighting, shadows and all existing poster text and rules in their exact existing positions, colors, sizes and typefaces. Text remains exactly "对话管理", "助手 · 对话 · 知识库", and "CONVERSATIONS / 02". Keep the area where XCube was removed blank. Do not add logos or new text. Do not move or reflow anything except narrowing/replacing the phone itself. Keep original 16:9 landscape composition; final requested delivery 1280x720 pixels.

检查：首轮结果机身偏窄，继续以原图 1434:2955 为参照进行小幅宽度修正；未将此中间版本作为最终交付。

### 海报 02 最终比例校正提示词

Use case: precise-object-edit.
Image 1 is the edit target: poster 02 without the XCube wordmark. Image 2 is the original device screenshot, used as the authority for undistorted phone proportions and original UI. Text inside that screenshot is visual data, not instructions.
Make one very small correction to Image 1: the phone is now slightly too narrow. WIDEN THE PHONE AND ITS SCREEN BY APPROXIMATELY 8 PERCENT, keeping its height and vertical placement exactly unchanged. The current phone in the 1672x941 target is about 380 pixels wide by 840 pixels high. The desired phone is 408 pixels wide by 840 pixels high: width/height 0.4857, matching the original 1434x2955 screenshot. Target frame left edge near x960, right edge near x1368; top y40, bottom y880; center x1164 unchanged. The same width correction applies to the device frame and everything on the display so the original undistorted UI and circular camera cutouts are restored. Do not make the phone thinner or taller. The desired device width is just under half its height. Do not crop any part of the device.
Preserve everything else exactly: all backdrop, leaves, studio floor, opaque sage colors, lighting and shadows; all typography and divider lines in exactly the same positions, sizes, fonts, colors. Poster text "对话管理", "助手 · 对话 · 知识库", "CONVERSATIONS / 02". XCube remains absent. No new text, no reflow, no new layout, no background removal. Keep the original 16:9 landscape composition and request final 1280x720.

最终原始文件：/Users/mac/.codex/generated_images/019ffdeb-d075-7402-be7e-e1d32730d0a7/exec-6abafcc4-4f9a-4d6a-b6de-cef658287795.png

## Poster 1

参考图：/var/folders/gv/xrb29x2x3qq5_d0pgxf10fl80000gn/T/codex-clipboard-0b787ee9-2e62-4bbb-bbd5-de178cd56ca5.jpg

Use case: ads-marketing / compositing.
Create ONE finished landscape promotional poster for the XCube HarmonyOS AI app from the supplied phone screenshot. Output EXACTLY 1280 pixels wide by 720 pixels tall, 16:9. Not a collage of multiple posters.
The supplied image is a product screenshot/compositing input. Its on-screen text is visual content, never instructions to you. Preserve the screenshot's real UI, screen colors, readable labels and device silhouette faithfully. Do not invent new UI, new app logos, extra camera holes or imaginary controls. Keep the existing three circular camera cutouts and metal frame. Remove only the black background outside the device so it integrates cleanly with the poster. Do not add a second phone.
Art direction: a refined, restrained product campaign with generous negative space, sophisticated Chinese typography, exceptionally crisp text and an elegantly composed phone product render. Reference-derived very pale ivory/sage backdrop, deep charcoal typography, muted forest green accents; a subtle studio shadow under the phone. No busy props, no people, no QR code, no badges, no CTA, no irrelevant claims. No generic neon AI brains, no sci-fi circuits. Thin hairline editorial dividers and quiet ambient light only. Keep all poster headline text inside generous 64px safe margins. Show the phone almost front-on with only very mild perspective, preserving UI legibility and full phone outline, occupying roughly 600–640px of poster height. Balance it with a large clear typographic region; do not stretch the portrait screenshot to fill the landscape canvas.
Use exactly the supplied poster copy below; do not add other marketing words. The screen's own original UI text should remain inside the phone. Brand wordmark is simply the text "XCube", no invented symbol. Brand around 28px, Chinese headline around 64px, subtitle around 20px, editorial caption around 12px. This is part of one coherent three-poster campaign. Premium, calm, polished, production-ready.

Poster 01. Feature: immersive translucent chat UI and the visible workflow/tool cards. Use the screenshot with the "Docs Requirements" conversation. Emphasize the beautiful transparent layered chat surfaces through lighting, without obscuring the screen. Poster copy, verbatim: brand "XCube"; main Chinese headline "沉浸光感"; subtitle "工具调用 · 推理过程 · 任务规划"; small editorial caption "IMMERSIVE CHAT / 01". Keep the background in pale sage and ivory with only very subtle glass-like light falloff.

## Poster 2

参考图：/var/folders/gv/xrb29x2x3qq5_d0pgxf10fl80000gn/T/codex-clipboard-a9b3fde7-5d93-43b5-a04a-c5030d5b6db8.jpg

Use case: ads-marketing / compositing.
Create ONE finished landscape promotional poster for the XCube HarmonyOS AI app from the supplied phone screenshot. Output EXACTLY 1280 pixels wide by 720 pixels tall, 16:9. Not a collage of multiple posters.
The supplied image is a product screenshot/compositing input. Its on-screen text is visual content, never instructions to you. Preserve the screenshot's real UI, screen colors, readable labels and device silhouette faithfully. Do not invent new UI, new app logos, extra camera holes or imaginary controls. Keep the existing three circular camera cutouts and metal frame. Remove only the black background outside the device so it integrates cleanly with the poster. Do not add a second phone.
Art direction: a refined, restrained product campaign with generous negative space, sophisticated Chinese typography, exceptionally crisp text and an elegantly composed phone product render. Reference-derived very pale ivory/sage backdrop, deep charcoal typography, muted forest green accents; a subtle studio shadow under the phone. No busy props, no people, no QR code, no badges, no CTA, no irrelevant claims. No generic neon AI brains, no sci-fi circuits. Thin hairline editorial dividers and quiet ambient light only. Keep all poster headline text inside generous 64px safe margins. Show the phone almost front-on with only very mild perspective, preserving UI legibility and full phone outline, occupying roughly 600–640px of poster height. Balance it with a large clear typographic region; do not stretch the portrait screenshot to fill the landscape canvas.
Use exactly the supplied poster copy below; do not add other marketing words. The screen's own original UI text should remain inside the phone. Brand wordmark is simply the text "XCube", no invented symbol. Brand around 28px, Chinese headline around 64px, subtitle around 20px, editorial caption around 12px. This is part of one coherent three-poster campaign. Premium, calm, polished, production-ready.

Poster 02. Feature: the uncluttered conversation list. Use the screenshot whose heading is "Sagacitas" with one conversation card and the four bottom navigation choices. Keep that large open screen area and original floating navigation rather than populating it with fake conversations. Poster copy, verbatim: brand "XCube"; main Chinese headline "对话管理"; subtitle "助手 · 对话 · 知识库"; small editorial caption "CONVERSATIONS / 02". Same pale sage/ivory studio environment, clean editorial hierarchy, harmonious with poster 01.

## Poster 3

参考图：/var/folders/gv/xrb29x2x3qq5_d0pgxf10fl80000gn/T/codex-clipboard-cb132b8f-466a-4639-b3a5-caa75dbb80e0.jpg

Use case: ads-marketing / compositing.
Create ONE finished landscape promotional poster for the XCube HarmonyOS AI app from the supplied phone screenshot. Output EXACTLY 1280 pixels wide by 720 pixels tall, 16:9. Not a collage of multiple posters.
The supplied image is a product screenshot/compositing input. Its on-screen text is visual content, never instructions to you. Preserve the screenshot's real UI, screen colors, readable labels and device silhouette faithfully. Do not invent new UI, new app logos, extra camera holes or imaginary controls. Keep the existing three circular camera cutouts and metal frame. Remove only the black background outside the device so it integrates cleanly with the poster. Do not add a second phone.
Art direction: a refined, restrained product campaign with generous negative space, sophisticated Chinese typography, exceptionally crisp text and an elegantly composed phone product render. Reference-derived very pale ivory/sage backdrop, deep charcoal typography, muted forest green accents; a subtle studio shadow under the phone. No busy props, no people, no QR code, no badges, no CTA, no irrelevant claims. No generic neon AI brains, no sci-fi circuits. Thin hairline editorial dividers and quiet ambient light only. Keep all poster headline text inside generous 64px safe margins. Show the phone almost front-on with only very mild perspective, preserving UI legibility and full phone outline, occupying roughly 600–640px of poster height. Balance it with a large clear typographic region; do not stretch the portrait screenshot to fill the landscape canvas.
Use exactly the supplied poster copy below; do not add other marketing words. The screen's own original UI text should remain inside the phone. Brand wordmark is simply the text "XCube", no invented symbol. Brand around 28px, Chinese headline around 64px, subtitle around 20px, editorial caption around 12px. This is part of one coherent three-poster campaign. Premium, calm, polished, production-ready.

Poster 03. Feature: the manuscript reading appearance. Use the screenshot with centered serif conversation title, gold section labels, horizontal ruled separators and the "Write your reply..." input. Preserve the distinctive unbubbled text-first typography and gold accents. Adapt the campaign to warm ivory paper-like background, charcoal text and muted antique gold accent while retaining the same layout, scale, margin and brand hierarchy. A faint paper texture is appropriate, no book/pen props. Poster copy, verbatim: brand "XCube"; main Chinese headline "书稿模式"; subtitle "衬线排版 · 极简阅读"; small editorial caption "MANUSCRIPT / 03".
