/**
 * Input validation middleware.
 *
 * Validates `req.query` and/or `req.body` against a simple schema object.
 *
 * Schema format:
 *   {
 *     query: { paramName: { type: 'string'|'number'|'boolean', required: boolean } },
 *     body:  { fieldName: { type: 'string'|'number'|'boolean'|'array'|'object', required: boolean } }
 *   }
 *
 * @param {{ query?: object, body?: object }} schema
 * @returns Express middleware
 */
function validate(schema) {
  return function validateMiddleware(req, res, next) {
    const errors = [];

    if (schema.query) {
      validateObject(req.query, schema.query, 'query', errors);
    }

    if (schema.body) {
      validateObject(req.body, schema.body, 'body', errors);
    }

    if (errors.length > 0) {
      return res.status(400).json({ errors });
    }

    next();
  };
}

function validateObject(source, rules, location, errors) {
  if (!source) source = {};

  for (const [field, rule] of Object.entries(rules)) {
    const value = source[field];

    // Required check
    if (rule.required && (value === undefined || value === null || value === '')) {
      errors.push({ field, location, message: `${field} is required` });
      continue;
    }

    // Skip type check if value is absent and not required
    if (value === undefined || value === null) continue;

    // Type check
    if (rule.type) {
      if (!matchesType(value, rule.type, location)) {
        errors.push({
          field,
          location,
          message: `${field} must be of type ${rule.type}`,
        });
      }
    }
  }
}

function matchesType(value, expectedType, location) {
  switch (expectedType) {
    case 'string':
      return typeof value === 'string';
    case 'number':
      // Query params arrive as strings — accept numeric strings in query
      if (location === 'query') return !isNaN(Number(value));
      return typeof value === 'number' && !isNaN(value);
    case 'boolean':
      if (location === 'query') return value === 'true' || value === 'false';
      return typeof value === 'boolean';
    case 'array':
      return Array.isArray(value);
    case 'object':
      return typeof value === 'object' && !Array.isArray(value);
    default:
      return true;
  }
}

module.exports = validate;
