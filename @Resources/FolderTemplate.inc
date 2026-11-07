[FolderIcon]
Meter=Shape
X=32
Y=18
Shape=Rectangle 0,0,48,48,12 | Fill Color 38,44,58,235 | StrokeWidth 1.5 | Stroke Color 255,255,255,40
DynamicVariables=1
LeftMouseUpAction=[!ShowMeterGroup PanelContent][!Redraw]

[FolderLabel]
Meter=String
X=56
Y=70
W=96
H=26
Text=#FolderName#
FontFace=Segoe UI
FontSize=10
FontColor=245,247,255,255
StringAlign=Center
ClipString=1
AntiAlias=1
DynamicVariables=1
LeftMouseUpAction=[!ShowMeterGroup PanelContent][!Redraw]

[PanelBackground]
Meter=Shape
Group=PanelContent
X=18
Y=104
Shape=Rectangle 0,0,#PanelWidth#,#PanelHeight#,8 | Fill Color 29,33,44,250 | StrokeWidth 1 | Stroke Color 50,58,78,255
Hidden=1

[PanelTitle]
Meter=String
Group=PanelContent
X=34
Y=118
W=(#PanelWidth#-60)
H=24
Text=#FolderName#
FontFace=Segoe UI
FontSize=12
FontWeight=700
FontColor=245,247,255,255
AntiAlias=1
Hidden=1
DynamicVariables=1

[PanelClose]
Meter=String
Group=PanelContent
X=(18+#PanelWidth#-24)
Y=116
W=24
H=24
Text=[\x00D7]
FontFace=Segoe UI
FontSize=14
FontColor=175,185,205,255
StringAlign=Center
AntiAlias=1
Hidden=1
LeftMouseUpAction=[!HideMeterGroup PanelContent][!Redraw]
DynamicVariables=1
