// config/database.ts

export default ({ env }) => {
  // This is the configuration for your AWS production deployment
  if (env('NODE_ENV') === 'production') {
    return {
      connection: {
        client: 'postgres',
        connection: {
          host: env('DATABASE_HOST'),
          port: env.int('DATABASE_PORT'),
          database: env('DATABASE_NAME'),
          user: env('DATABASE_USERNAME'),
          password: env('DATABASE_PASSWORD'),
        },
        debug: false,
      },
    };
  }

  // This is the default configuration for your local development
  return {
    connection: {
      client: 'sqlite',
      connection: {
        filename: env('DATABASE_FILENAME', './.tmp/data.db'),
      },
      useNullAsDefault: true,
    },
  };
};