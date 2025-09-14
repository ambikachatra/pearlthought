# This Dockerfile is for LOCAL DEVELOPMENT ONLY

FROM node:18-alpine

# Set the working directory
WORKDIR /opt/app

# Copy package manifests and install dependencies
COPY ./package.json ./package-lock.json ./
RUN npm install

# Copy all your source code into the container
# This includes the important 'config' directory
COPY . .

# Expose the port
EXPOSE 1337

# The default command to run when the container starts
CMD ["npm", "run", "develop"]