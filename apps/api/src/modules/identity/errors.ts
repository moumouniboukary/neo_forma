export class IdentityError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly statusCode: number = 400
  ) {
    super(message);
    this.name = "IdentityError";
  }
}

export function isIdentityError(err: unknown): err is IdentityError {
  return err instanceof IdentityError;
}
