FROM python:3.12-slim
RUN useradd --system --no-create-home app
WORKDIR /app
COPY --chmod=644 requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chmod=644 app.py .
USER app
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--access-logfile", "-", "app:app"]
