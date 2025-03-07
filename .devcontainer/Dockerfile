FROM alpine:latest
RUN apk update && apk add git vim curl
RUN mkdir ~/.vim
RUN mkdir ~/.vim/bundle
RUN git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim