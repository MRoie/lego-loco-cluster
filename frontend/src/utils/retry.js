/**
 * Retry Strategy Utility
 * Implements exponential backoff for robust operation retries.
 */

import { createLogger } from './logger';

const logger = createLogger('RetryStrategy');

export class RetryStrategy {
    constructor(maxAttempts = 5, baseDelayMs = 1000, maxDelayMs = 30000) {
        this.maxAttempts = maxAttempts;
        this.baseDelayMs = baseDelayMs;
        this.maxDelayMs = maxDelayMs;
        this.currentAttempt = 0;
    }

    async execute(fn, onRetry) {
        while (this.currentAttempt < this.maxAttempts) {
            try {
                const result = await fn();
                if (this.currentAttempt > 0) {
                    logger.info('Operation succeeded after retries', { attempts: this.currentAttempt });
                }
                this.currentAttempt = 0;  // Reset on success
                return result;
            } catch (error) {
                this.currentAttempt++;

                if (this.currentAttempt >= this.maxAttempts) {
                    logger.error('Max retry attempts exceeded', {
                        maxAttempts: this.maxAttempts,
                        error: error.message
                    });
                    throw new Error(`Max retry attempts (${this.maxAttempts}) exceeded: ${error.message}`);
                }

                // Calculate delay with exponential backoff: base * 2^(attempt-1)
                // Add jitter to prevent thundering herd
                const exponentialDelay = this.baseDelayMs * Math.pow(2, this.currentAttempt - 1);
                const jitter = Math.random() * 0.1 * exponentialDelay; // 10% jitter
                const delay = Math.min(exponentialDelay + jitter, this.maxDelayMs);

                logger.warn('Retry attempt failed, scheduling retry', {
                    attempt: this.currentAttempt,
                    maxAttempts: this.maxAttempts,
                    delayMs: Math.round(delay),
                    error: error.message
                });

                if (onRetry) {
                    onRetry(this.currentAttempt, delay, error);
                }

                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }

    reset() {
        this.currentAttempt = 0;
    }
}
