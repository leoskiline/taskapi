// Package task contém o domínio da aplicação: o modelo, as regras de
// validação, a porta de persistência e os handlers HTTP.
package task

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

// Status é o estado de uma tarefa. Tipo próprio em vez de string solta para
// que valores inválidos sejam pegos na validação, não no banco.
type Status string

const (
	StatusTodo  Status = "todo"
	StatusDoing Status = "doing"
	StatusDone  Status = "done"
)

func (s Status) Valid() bool {
	switch s {
	case StatusTodo, StatusDoing, StatusDone:
		return true
	default:
		return false
	}
}

type Task struct {
	ID        int64     `json:"id"`
	Title     string    `json:"title"`
	Status    Status    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// ErrNotFound é devolvido pelo Store quando o registro não existe. O handler
// traduz para 404 — o domínio não sabe o que é um código HTTP.
var ErrNotFound = errors.New("tarefa não encontrada")

// ValidationError carrega o campo problemático para virar um 400 com corpo útil.
type ValidationError struct {
	Field   string
	Message string
}

func (e ValidationError) Error() string {
	return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

const maxTitleLen = 200

type CreateInput struct {
	Title  string `json:"title"`
	Status Status `json:"status"`
}

// Validate normaliza e valida a entrada. Status vazio vira "todo" — default
// no domínio, não no banco, para que a regra seja testável sem Postgres.
func (in *CreateInput) Validate() error {
	in.Title = strings.TrimSpace(in.Title)

	if in.Title == "" {
		return ValidationError{Field: "title", Message: "é obrigatório"}
	}
	if len(in.Title) > maxTitleLen {
		return ValidationError{Field: "title", Message: fmt.Sprintf("no máximo %d caracteres", maxTitleLen)}
	}
	if in.Status == "" {
		in.Status = StatusTodo
	}
	if !in.Status.Valid() {
		return ValidationError{Field: "status", Message: "deve ser todo, doing ou done"}
	}
	return nil
}

type UpdateInput struct {
	Title  string `json:"title"`
	Status Status `json:"status"`
}

func (in *UpdateInput) Validate() error {
	in.Title = strings.TrimSpace(in.Title)

	if in.Title == "" {
		return ValidationError{Field: "title", Message: "é obrigatório"}
	}
	if len(in.Title) > maxTitleLen {
		return ValidationError{Field: "title", Message: fmt.Sprintf("no máximo %d caracteres", maxTitleLen)}
	}
	if !in.Status.Valid() {
		return ValidationError{Field: "status", Message: "deve ser todo, doing ou done"}
	}
	return nil
}
