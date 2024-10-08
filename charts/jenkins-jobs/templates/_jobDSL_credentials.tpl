{{/* vim: set filetype=mustache: */}}
{{/******************* JobDSL Credentials templates ***********************/}}
{{/*
Generate the job-dsl definition main credentials structure in a Job definition
*/}}
{{- define "common-credentials-job-dsl-definition" -}}
  {{- if .credentials }}
    {{- /* Prepare the 2 dicts of credentials: bindings and hackishxml */}}
    {{- $credentialsWithBindings := dict }}
    {{- $credentialsWithHackishXml := dict }}
    {{- range $credentialId, $credentialDef := .credentials }}
      {{- $credentialKind := .kind }}
      {{- if empty $credentialKind }}
        {{- /* Try to gues which kind of credential if not specified */}}
        {{- if and (hasKey $credentialDef "fileName") (hasKey $credentialDef "secretBytes") }}
          {{- $credentialKind = "file" }}
        {{- else if and (hasKey $credentialDef "azureEnvironmentName") (hasKey $credentialDef "clientId") }}
          {{- $credentialKind = "azure-serviceprincipal" }}
        {{- else if and (hasKey $credentialDef "privateKey") (hasKey $credentialDef "username") }}
          {{- $credentialKind = "ssh" }}
        {{- else if and (hasKey $credentialDef "password") (hasKey $credentialDef "username") }}
          {{- $credentialKind = "usernamePassword" }}
        {{- else if and (hasKey $credentialDef "accessKey") (hasKey $credentialDef "secretKey") }}
          {{- $credentialKind = "aws" }}
        {{- else if and (or (hasKey $credentialDef "appID") (hasKey $credentialDef "appId") (hasKey $credentialDef "appid")) (hasKey $credentialDef "privateKey") }}
          {{- $credentialKind = "githubapp" }}
        {{- else }}
          {{- $credentialKind = "string" }}
        {{- end }}
      {{- end }}
      {{- $credentialDef = set $credentialDef "kind" $credentialKind }}
      {{- if has $credentialKind (list "string" "file" "azure-serviceprincipal" "ssh" "githubapp") }}
        {{- $_ := set $credentialsWithHackishXml $credentialId $credentialDef }}
      {{- else if has $credentialKind (list "usernamePassword" "aws") }}
        {{- $_ := set $credentialsWithBindings $credentialId $credentialDef }}
      {{- end }}
    {{- end }}

properties {
  folderCredentialsProperty {
    domainCredentials {
      domainCredentials {
        domain {
          name('{{ .name }}')
          description('Credentials for the job {{ .name }}')
        }
    {{- if $credentialsWithBindings }}
{{ include "binding-credentials-dsl-definition" $credentialsWithBindings | indent 8 }}
    {{- end }}
      }
    }
  }
}
    {{- /* Some credentials does not have a job-dsl binding (e.g. having a human-usable syntax) -
    - https://issues.jenkins.io/browse/JENKINS-59971?focusedCommentId=383059&page=com.atlassian.jira.plugin.system.issuetabpanels%3Acomment-tabpanel#comment-383059
    - https://issues.jenkins.io/browse/JENKINS-57435
    - https://github.com/jenkinsci/job-dsl-plugin/pull/1202
    */}}
    {{- if $credentialsWithHackishXml }}
{{- include "hackishxml-credentials-dsl-definition" $credentialsWithHackishXml }}
    {{- end }}
  {{- end }}
{{- end -}}

{{/*
Generate the job-dsl definition of credentials with bindings
*/}}
{{- define "binding-credentials-dsl-definition" -}}
credentials {
  {{- range $credentialsId, $credentialDef := . }}
    {{- $kind := .kind | default "string" }}
    {{- if eq $kind "usernamePassword" }}
{{ include "username-password-credential-dsl-definition" (merge $credentialDef (dict "id" $credentialsId )) | indent 2 }}
    {{- else if eq $kind "aws"}}
{{ include "aws-credential-dsl-definition" (merge $credentialDef (dict "id" $credentialsId )) | indent 2 }}
    {{- end }}
  {{- end }}
}
{{- end -}}

{{/*
Generate the common job-dsl definition of a credential
*/}}
{{- define "credential-common-dsl-definition" -}}
scope('{{ .scope | default "GLOBAL" }}')
id('{{ .id }}')
description('{{ .description | default .id }}')
{{- end }}

{{/*
Generate the job-dsl definition of credentials with NO bindings, eg. through configuration of the XML configuration file
*/}}
{{- define "hackishxml-credentials-dsl-definition" -}}
{{/* Definition through the XML tree as per https://issues.jenkins.io/browse/JENKINS-59971 */}}
configure { node ->
  def configNode = node / 'properties' /  'com.cloudbees.hudson.plugins.folder.properties.FolderCredentialsProvider_-FolderCredentialsProperty' /  'domainCredentialsMap' / 'entry' / 'java.util.concurrent.CopyOnWriteArrayList'
  {{- range $credentialsId, $credentialDef := . }}
    {{- $credential := merge $credentialDef (dict "id" $credentialsId ) -}}
    {{- if empty .kind }}
{{ include "string-credential-dsl-definition" $credential | indent 2 }}
    {{- else if eq .kind "string" }}
{{ include "string-credential-dsl-definition" $credential | indent 2 }}
    {{- else if eq .kind "file" }}
{{ include "file-credential-dsl-definition" $credential | indent 2 }}
    {{- else if eq .kind "azure-serviceprincipal" }}
{{ include "azuresp-credential-dsl-definition" $credential | indent 2 }}
    {{- else if eq .kind "ssh" }}
{{ include "ssh-credential-dsl-definition" $credential | indent 2 }}
    {{- else if eq .kind "githubapp" }}
{{ include "githubapp-credential-dsl-definition" $credential | indent 2 }}
    {{- end -}}
  {{- end }}
}
{{- end -}}


{{/*
Generate the job-dsl definition of a string credential
*/}}
{{- define "string-credential-dsl-definition" }}
configNode << 'org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl'(plugin: 'plain-credentials') {
{{ include "credential-common-dsl-definition" . | indent 2 }}
  secret(hudson.util.Secret.fromString('{{ .secret }}').getEncryptedValue())
}
{{- end }}

{{/*
Generate the job-dsl definition of a file credential
*/}}
{{- define "file-credential-dsl-definition" }}
configNode << 'org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl' {
{{ include "credential-common-dsl-definition" . | indent 2 }}
  fileName('{{ .fileName }}')
  secretBytes(com.cloudbees.plugins.credentials.SecretBytes.fromBytes(new String('{{ .secretBytes }}').decodeBase64()).toString())
}
{{- end }}

{{/*
Generate the job-dsl definition of a file credential
*/}}
{{- define "azuresp-credential-dsl-definition" }}
configNode << 'com.microsoft.azure.util.AzureCredentials'(plugin: 'azure-credentials') {
{{ include "credential-common-dsl-definition" . | indent 2 }}
  data {
    subscriptionId(hudson.util.Secret.fromString('{{ .subscriptionId }}').getEncryptedValue())
    clientId(hudson.util.Secret.fromString('{{ .clientId }}').getEncryptedValue())
    {{- if .clientSecret }}
    clientSecret(hudson.util.Secret.fromString('{{ .clientSecret }}').getEncryptedValue())
    {{- end }}
    {{- if .certificateId }}
    certificateId('{{ .certificateId }}')
    {{- end }}
    tenant(hudson.util.Secret.fromString('{{ .tenant }}').getEncryptedValue())
    azureEnvironmentName('{{ .azureEnvironmentName }}')
  }
}
{{- end }}

{{/*
Generate the job-dsl definition of a usernamePassword credential
*/}}
{{- define "username-password-credential-dsl-definition" -}}
usernamePassword {
{{ include "credential-common-dsl-definition" . | indent 2 }}
  username('{{ .username }}')
  password('{{ .password }}')
  usernameSecret({{ .usernameSecret | default false}})
}
{{- end }}


{{/*
Generate the job-dsl definition of an aws credential
*/}}
{{- define "aws-credential-dsl-definition" -}}
awsCredentialsImpl {
{{ include "credential-common-dsl-definition" . | indent 2 }}
  accessKey('{{ .accessKey }}')
  secretKey('{{ .secretKey }}')
  iamRoleArn('{{ .iamRoleArn }}')
  iamMfaSerialNumber('{{ .iamMfaSerialNumber }}')
  iamExternalId('{{ .iamExternalId }}')
  {{- if .stsTokenDuration }}
  stsTokenDuration('{{ .stsTokenDuration }}')
  {{- end }}
}
{{- end }}

{{/*
Generate the job-dsl definition of a ssh username + key credential
*/}}
{{- define "ssh-credential-dsl-definition" -}}
configNode << 'com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey' {
{{ include "credential-common-dsl-definition" . | indent 2 }}
  username('{{ .username }}')
  {{- if .passphrase }}
  passphrase('{{ .passphrase }}')
  {{- end }}
  usernameSecret({{ .usernameSecret | default false}})
  privateKeySource(class:"com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey\$DirectEntryPrivateKeySource") {
    privateKey('''{{ .privateKey }}''')

  }
}
{{- end }}

{{/*
Generate the job-dsl definition of a Github App credential
*/}}
{{- define "githubapp-credential-dsl-definition" -}}
configNode << 'org.jenkinsci.plugins.github__branch__source.GitHubAppCredentials'(plugin: 'github-branch-source') {
{{ include "credential-common-dsl-definition" . | indent 2 }}
  appID('{{ coalesce .appID .appId .appid }}')
  privateKey('''{{ .privateKey }}''')
  {{- if .owner }}
  owner('{{ .owner }}')
  {{- end }}
}
{{- end }}
