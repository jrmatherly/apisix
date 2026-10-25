/**
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { routesPom } from '@e2e/pom/routes';
import { e2eReq } from '@e2e/utils/req';
import { test } from '@e2e/utils/test';
import { uiGoto } from '@e2e/utils/ui';
import { expect } from '@playwright/test';

import { putRouteReq } from '@/apis/routes';
import { API_ROUTES } from '@/config/constant';

const routeId = 'test-vars-admin-api';

test.beforeAll(async () => {
  await e2eReq.delete(`${API_ROUTES}/${routeId}`).catch(() => {
    // Ignore cleanup errors; route may not exist yet.
  });
});

test.afterAll(async () => {
  await e2eReq.delete(`${API_ROUTES}/${routeId}`).catch(() => {
    // Ignore cleanup errors; route may already be deleted.
  });
});

test('route with vars created via Admin API', async ({ page }) => {
  await test.step('create route with vars via Admin API', async () => {
    await putRouteReq(e2eReq, {
      id: routeId,
      name: routeId,
      uri: '/test-vars-route',
      methods: ['GET', 'POST'],
      upstream: {
        type: 'roundrobin',
        nodes: [{ host: 'httpbin.org', port: 80, weight: 1 }],
      },
      vars: [
        [
          'uri',
          '~~',
          '^/(.*)/v1beta/models/(gemini-3-pro-preview)(?::[A-Za-z0-9._-]+)?$',
        ],
      ],
    });
  });

  await test.step('view route detail without error', async () => {
    // Navigate directly to the route detail page to avoid flaky table lookups
    await uiGoto(page, '/routes/detail/$id', { id: routeId });

    // Verify the detail page loaded successfully
    await routesPom.isDetailPage(page);

    const name = page.getByLabel('Name', { exact: true }).first();
    await expect(name).toHaveValue(routeId);
  });
});