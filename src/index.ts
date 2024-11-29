import { registerPlugin } from '@capacitor/core';

import type { HealthPlugin } from './definitions';

export const Health = registerPlugin<HealthPlugin>('HealthPlugin', {});

export * from './definitions';
