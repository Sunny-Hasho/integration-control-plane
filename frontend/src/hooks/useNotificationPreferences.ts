/**
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import { useCallback, useState } from 'react';

const STORAGE_KEY = 'icp_notification_prefs';

interface NotificationPreferences {
  runtimeStatusEnabled: boolean;
}

function loadPrefs(): NotificationPreferences {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      return {
        runtimeStatusEnabled: typeof parsed.runtimeStatusEnabled === 'boolean' ? parsed.runtimeStatusEnabled : true,
      };
    }
  } catch {
    // ignore parse errors — fall through to default
  }
  return { runtimeStatusEnabled: true };
}

export function useNotificationPreferences() {
  const [prefs, setPrefs] = useState<NotificationPreferences>(loadPrefs);

  const setRuntimeStatusEnabled = useCallback((enabled: boolean) => {
    setPrefs((prev) => {
      const next = { ...prev, runtimeStatusEnabled: enabled };
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      } catch {
        // ignore storage errors (e.g. private browsing quota)
      }
      return next;
    });
  }, []);

  return { ...prefs, setRuntimeStatusEnabled };
}
