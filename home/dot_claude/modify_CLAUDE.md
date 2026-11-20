{{- /* chezmoi:modify-template */ -}}
{{- includeTemplate "ensure-line" (dict "stdin" .chezmoi.stdin "line" "@ENGINEERING.md") -}}
