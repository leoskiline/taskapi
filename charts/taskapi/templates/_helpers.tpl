{{/*
Nome base do release. O truncamento em 63 caracteres não é decoração: é o
limite de um label do Kubernetes, e estourá-lo faz o install falhar com um erro
que não menciona tamanho nenhum.
*/}}
{{- define "taskapi.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "taskapi.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Labels recomendados pelo Kubernetes. Ter um conjunto padronizado é o que
permite `kubectl get all -l app.kubernetes.io/instance=<release>` devolver
tudo que pertence a este release — e nada além.
*/}}
{{- define "taskapi.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "taskapi.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels são IMUTÁVEIS em um Deployment já criado. Por isso ficam
separados dos labels gerais: mudar `version` não pode quebrar o upgrade.
*/}}
{{- define "taskapi.selectorLabels" -}}
app.kubernetes.io/name: {{ include "taskapi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
A URL do banco em um lugar só. Com o subchart ligado, o host é o Service que o
chart da Bitnami cria (<release>-postgresql); desligado, usa o banco externo.
Centralizar aqui evita a URL divergir entre o initContainer e o container da
aplicação — que é exatamente o tipo de erro que só aparece em produção.
*/}}
{{- define "taskapi.databaseURL" -}}
{{- if .Values.postgresql.enabled -}}
postgres://{{ .Values.postgresql.auth.username }}:{{ .Values.postgresql.auth.password }}@{{ .Release.Name }}-postgresql:5432/{{ .Values.postgresql.auth.database }}?sslmode=disable
{{- else -}}
{{- required "externalDatabase.url é obrigatório quando postgresql.enabled = false" .Values.externalDatabase.url -}}
{{- end -}}
{{- end }}

{{- define "taskapi.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag -}}
{{- end }}
