[Rainmeter]
OnRefreshAction=[!KeepOnScreen 0]
OnUnfocusAction=[!CommandMeasure MeasureToggle "ClosePanel()"]

[Variables]
IsOpen=0
AnimScale=1
AnimAlpha=255
AnimShiftX=0
AnimShiftY=0
PanelMatrix=1;0;0;1;0;0
SelW=96
SelH=84
OrigX=0
OrigY=0
PanelX=18
PanelY=104
IconOffsetX=0
IconOffsetY=0
HoverX=0
HoverY=0
HoverW=98
HoverH=88
HoverAlpha=0

[MeasureToggle]
Measure=Script
ScriptFile=#@#Scripts\FolderPopup.lua
UpdateDivider=-1

; --- SUBTLE AMBIENT OUTER HALO FOR FOLDER SQUIRCLE (HOLLOW RINGS) ---
[FolderIconGlow]
Meter=Shape
X=(29 + #IconOffsetX#)
Y=(15 + #IconOffsetY#)
Shape=Rectangle 2,2.5,50,50,14 | Fill Color 0,0,0,0 | StrokeWidth 2.4 | Stroke Color #PopupGlowRGB#,(Round(#FolderOuterGlowA1# * #FolderAlphaScale#))
Shape2=Rectangle 0.8,1.5,52.4,52.4,15 | Fill Color 0,0,0,0 | StrokeWidth 1.6 | Stroke Color #PopupGlowRGB#,(Round(#FolderOuterGlowA2# * #FolderAlphaScale#))
DynamicVariables=1

; --- UNIFIED LIQUID GLASS FOLDER SQUIRCLE (48x48) ---
[FolderIcon]
Meter=Shape
X=(32 + #IconOffsetX#)
Y=(18 + #IconOffsetY#)
Shape=Rectangle 0,0,48,48,13 | Fill LinearGradient FolderGlassFill | StrokeWidth 1.2 | Stroke Color #FolderBorderRGB#,(Round(#FolderBorderAlpha# * #FolderAlphaScale#))
Shape2=Rectangle 1,1,46,46,12 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke LinearGradient UnifiedInnerGlow
FolderGlassFill=135 | #FolderFillTopRGB#,(Round(195 * #FolderAlphaScale#)) ; 0.0 | #FolderFillRGB#,(Round(185 * #FolderAlphaScale#)) ; 0.55 | #FolderFillBotRGB#,(Round(198 * #FolderAlphaScale#)) ; 1.0
UnifiedInnerGlow=135 | #FolderGlowRGB#,(Round(#FolderGlowAlpha# * #FolderAlphaScale#)) ; 0.0 | #FolderGlowRGB#,0 ; 0.65
DynamicVariables=1
MouseActionCursorName=HAND
LeftMouseUpAction=[!CommandMeasure MeasureToggle "TogglePanel()"]

[FolderLabel]
Meter=String
X=(56 + #IconOffsetX#)
Y=(68 + #IconOffsetY#)
W=78
H=32
Text=#FolderName#
FontFace=Segoe UI
FontSize=9
FontWeight=400
FontColor=255,255,255,255
StringAlign=Center
StringEffect=Border
FontEffectColor=0,0,0,220
ClipString=2
AntiAlias=1
DynamicVariables=1
MouseActionCursorName=HAND
LeftMouseUpAction=[!CommandMeasure MeasureToggle "TogglePanel()"]

; --- EXPANDED TINTED OUTER DROP-SHADOW GLOW (HOLLOW CONCENTRIC RINGS) ---
[PanelGlow]
Meter=Shape
Group=PanelContent
X=((#PanelX# + #AnimShiftX# - 11) * #IsOpen#)
Y=((#PanelY# + #AnimShiftY# - 11) * #IsOpen#)
Shape=Rectangle 11.5,11.5,(((#PanelWidth# * #AnimScale#) + 3) * #IsOpen#),(((#PanelHeight# * #AnimScale#) + 3) * #IsOpen#),((18 * #AnimScale#) + 1.5) | Fill Color 0,0,0,0 | StrokeWidth (3.2 * #IsOpen#) | Stroke Color #PopupGlowRGB#,(Round(#PopupGlowA1# * #PopupAlphaScale# * #AnimAlpha# / 255))
Shape2=Rectangle 8.5,9.0,(((#PanelWidth# * #AnimScale#) + 9) * #IsOpen#),(((#PanelHeight# * #AnimScale#) + 9) * #IsOpen#),((18 * #AnimScale#) + 4.5) | Fill Color 0,0,0,0 | StrokeWidth (3.2 * #IsOpen#) | Stroke Color #PopupGlowRGB#,(Round(#PopupGlowA2# * #PopupAlphaScale# * #AnimAlpha# / 255))
Shape3=Rectangle 5.5,6.5,(((#PanelWidth# * #AnimScale#) + 15) * #IsOpen#),(((#PanelHeight# * #AnimScale#) + 15) * #IsOpen#),((18 * #AnimScale#) + 7.5) | Fill Color 0,0,0,0 | StrokeWidth (3.2 * #IsOpen#) | Stroke Color #PopupGlowRGB#,(Round(#PopupGlowA3# * #PopupAlphaScale# * #AnimAlpha# / 255))
Shape4=Rectangle 2.5,4.0,(((#PanelWidth# * #AnimScale#) + 21) * #IsOpen#),(((#PanelHeight# * #AnimScale#) + 21) * #IsOpen#),((18 * #AnimScale#) + 10.5) | Fill Color 0,0,0,0 | StrokeWidth (3.2 * #IsOpen#) | Stroke Color #PopupGlowRGB#,(Round(#PopupGlowA4# * #PopupAlphaScale# * #AnimAlpha# / 255))
Hidden=1
DynamicVariables=1

; --- ANIMATED LIQUID GLASS POPUP PANEL ---
[PanelBackground]
Meter=Shape
Padding=2,2,2,2
Group=PanelContent
X=((#PanelX# + #AnimShiftX#) * #IsOpen#)
Y=((#PanelY# + #AnimShiftY#) * #IsOpen#)
Shape=Rectangle 0,0,(#PanelWidth# * #AnimScale# * #IsOpen#),(#PanelHeight# * #AnimScale# * #IsOpen#),(18 * #AnimScale#) | Fill LinearGradient PopupGlassFill | StrokeWidth (1.2 * #IsOpen#) | Stroke Color #PopupBorderRGB#,(Round(#PopupBorderAlpha# * #PopupAlphaScale# * #AnimAlpha# / 255))
Shape2=Rectangle 1,1,(Max(0, (#PanelWidth# * #AnimScale#) - 2) * #IsOpen#),(Max(0, (#PanelHeight# * #AnimScale#) - 2) * #IsOpen#),(13 * #AnimScale#) | Fill Color 0,0,0,0 | StrokeWidth (#IsOpen#) | Stroke LinearGradient UnifiedInnerGlow
PopupGlassFill=135 | #PopupFillTopRGB#,(Round(236 * #PopupAlphaScale# * #AnimAlpha# / 255)) ; 0.0 | #PopupFillRGB#,(Round(232 * #PopupAlphaScale# * #AnimAlpha# / 255)) ; 0.55 | #PopupFillBotRGB#,(Round(238 * #PopupAlphaScale# * #AnimAlpha# / 255)) ; 1.0
UnifiedInnerGlow=135 | #PopupInnerGlowRGB#,(Round(#PopupInnerGlowAlpha# * #PopupAlphaScale# * #AnimAlpha# / 255)) ; 0.0 | #PopupInnerGlowRGB#,0 ; 0.65
Hidden=1
DynamicVariables=1
LeftMouseUpAction=[!CommandMeasure MeasureToggle "ClearSelection()"]

; Idle-only highlight meters (excluded from PanelContent so they skip animation ticks)
[HoverHighlight]
Meter=Shape
X=(#PanelX# + #HoverX#)
Y=(#PanelY# + #HoverY#)
Shape=Rectangle 0,0,#HoverW#,#HoverH#,10 | Fill Color 255,255,255,(Round(28 * #HoverAlpha#)) | StrokeWidth 1 | Stroke Color 255,255,255,(Round(55 * #HoverAlpha#))
Hidden=1
DynamicVariables=1
UpdateDivider=-1

[SelectionHighlight]
Meter=Shape
X=0
Y=0
Shape=Rectangle 0,0,#SelW#,#SelH#,10 | Fill Color #SelFillRGB#,36 | StrokeWidth 1.2 | Stroke Color #SelBorderRGB#,165
Hidden=1
DynamicVariables=1

[PanelTitle]
Meter=String
Group=PanelContent
X=(#PanelX# + 16)
Y=(#PanelY# + 14)
W=(#PanelWidth# - 60)
H=24
Text=#FolderName#
FontFace=Segoe UI
FontSize=12
FontWeight=700
FontColor=245,247,255,#AnimAlpha#
AntiAlias=1
Hidden=1
DynamicVariables=1
TransformationMatrix=#PanelMatrix#

[PanelClose]
Meter=String
Group=PanelContent
X=(#PanelX# + #PanelWidth# - 24)
Y=(#PanelY# + 12)
W=24
H=24
Text=[\x00D7]
FontFace=Segoe UI
FontSize=14
FontColor=175,185,205,#AnimAlpha#
StringAlign=Center
AntiAlias=1
Hidden=1
MouseActionCursorName=HAND
LeftMouseUpAction=[!CommandMeasure MeasureToggle "ClosePanel()"]
DynamicVariables=1
TransformationMatrix=#PanelMatrix#
