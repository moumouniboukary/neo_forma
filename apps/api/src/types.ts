declare module "@fastify/jwt" {
  interface FastifyJWT {
    payload: {
      sub?: string;
      phone: string;
      purpose?: "otp_verified";
      otpPurpose?: "register" | "login" | "reset";
      typ?: "access";
      sid?: string;
    };
    user: {
      sub: string;
      phone: string;
      typ?: "access";
      sid?: string;
    };
  }
}

declare module "fastify" {
  interface FastifyInstance {
    authenticate: (
      request: import("fastify").FastifyRequest,
      reply: import("fastify").FastifyReply
    ) => Promise<void>;
  }
}

export type JwtUser = {
  sub: string;
  phone: string;
  typ?: "access";
  sid?: string;
};
