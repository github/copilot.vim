FROM alpine:latest
RUN apk update && apk add git vim curl wslview
RUN mkdir -p ~/.vim/bundle
RUN git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim