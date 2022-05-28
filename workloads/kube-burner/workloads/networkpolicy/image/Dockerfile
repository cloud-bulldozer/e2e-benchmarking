FROM python:slim
RUN apt update && \
      apt install -y curl
COPY ./pod-scraper.py pod-scraper.py
COPY ./requirements.txt requirements.txt
RUN pip install -r requirements.txt
COPY ./init.sh init.sh
