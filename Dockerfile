# ---- Builder Stage ----
FROM node:18-alpine AS builder
WORKDIR /opt/app

COPY ./package.json ./package-lock.json ./

# Use npm install for a more flexible installation that handles inconsistencies
RUN npm install

# Copy the rest of your application code
COPY . .

# Build the Strapi admin panel for production
RUN npm run build

# ---- Production Stage ----
FROM node:18-alpine
WORKDIR /opt/app

ENV NODE_ENV=production

COPY --from=builder /opt/app/dist ./dist
COPY --from=builder /opt/app/node_modules ./node_modules
COPY --from=builder /opt/app/package.json ./package.json
COPY --from=builder /opt/app/package-lock.json ./package-lock.json

COPY ./config ./config
COPY ./database ./database
COPY ./src ./src
COPY ./public ./public

EXPOSE 1337

CMD ["npm", "run", "start"]