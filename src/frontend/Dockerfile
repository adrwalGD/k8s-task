FROM golang:1.24-alpine AS builder
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download
COPY . .

RUN go build -o /go/bin/frontend .

FROM scratch
WORKDIR /src
COPY --from=builder /go/bin/frontend /src/server
COPY ./templates ./templates
COPY ./static ./static

EXPOSE 8080
ENTRYPOINT ["/src/server"]
