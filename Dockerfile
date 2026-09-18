FROM python:3.11-slim

# Install system dependencies for Playwright
RUN apt-get update && apt-get install -y     libgbm1     libnss3     libatk1.0-0     libatk-bridge2.0-0     libcups2     libdrm2     libxkbcommon0     libxcomposite1     libxdamage1     libxext6     libxfixes3     libxrandr2     libgbm1     libasound2     && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Playwright browsers
RUN playwright install chromium

# Copy the rest of the application
COPY . .

# The server uses the PORT environment variable
EXPOSE 8000

CMD ["python", "backend/server.py"]
